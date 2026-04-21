#import <CoreFoundation/CoreFoundation.h>
#import <errno.h>
#import <objc/runtime.h>
#import <string.h>
#import <stdlib.h>
#import <unistd.h>

#import "PLUContext.h"
#import "PLUMutableArray.h"
#import "PLUMutableDictionary.h"

extern const char **_CFGetProgname();
extern BOOL _NSIsNSString(id);
extern const CFStringRef kCFErrorDebugDescriptionKey;
extern CFDictionaryRef _CFBundleCopyInfoDictionaryForExecutableFileData(CFDataRef executableData,
                                                                        Boolean *isExecutableOrLibrary);
extern struct objc_class OBJC_CLASS_$_NSConstantArray;

typedef NS_ENUM(NSUInteger, PLUCommand) {
    PLUCommandLint = 0,
    PLUCommandHelp = 1,
    PLUCommandConvert = 2,
    PLUCommandConvertWithHeader = 3,
    PLUCommandInsert = 4,
    PLUCommandReplace = 5,
    PLUCommandRemove = 6,
    PLUCommandExtract = 7,
    PLUCommandPrint = 8,
    PLUCommandType = 9,
    PLUCommandCreate = 10,
};

typedef NS_ENUM(NSUInteger, PLUExpectType) {
    PLUExpectTypeNone = 0,
    PLUExpectTypeBool = 1,
    PLUExpectTypeInteger = 2,
    PLUExpectTypeFloat = 3,
    PLUExpectTypeString = 4,
    PLUExpectTypeArray = 5,
    PLUExpectTypeDictionary = 6,
    PLUExpectTypeDate = 7,
    PLUExpectTypeData = 8,
};

typedef NS_ENUM(NSInteger, PLUOperationFormat) {
    PLUOperationFormatType = -2,
    PLUOperationFormatNoConversion = -1,
    PLUOperationFormatXML1 = 100,
    PLUOperationFormatBinary1 = 200,
    PLUOperationFormatJSON = 1000,
    PLUOperationFormatSwift = 1001,
    PLUOperationFormatObjC = 1002,
    PLUOperationFormatRaw = 1003,
};

static NSString *const PLUExpectedTypeNames[] = {
    @"(any)",
    @"bool",
    @"integer",
    @"float",
    @"string",
    @"array",
    @"dictionary",
    @"date",
    @"data",
};

static NSString *const PLUEscapedDotPlaceholder = @"A_DOT_WAS_HERE";

struct PLUNSConstantArray {
    struct objc_class *isa;
    NSUInteger used;
    const void *list;
};

#if 1
/* An ugly hack to use contant literals, before Apple actually allow us to use it directly like how NSConstantString does */
static NSString *const PLULiteralEscapeTokensStorage[] __attribute__((used, section("__DATA_CONST,__objc_arraydata"))) = {
    @"\\b",
    @"\\s",
    @"\"",
    @"\\w",
    @"\\.",
    @"\\|",
    @"\\*",
    @"\\)",
    @"\\(",
};

static const struct PLUNSConstantArray PLULiteralEscapeTokensObject
    __attribute__((used, section("__DATA_CONST,__objc_arrayobj"))) = {
        .isa = &OBJC_CLASS_$_NSConstantArray,
        .used = sizeof(PLULiteralEscapeTokensStorage) / sizeof(PLULiteralEscapeTokensStorage[0]),
        .list = PLULiteralEscapeTokensStorage,
};
#else
static NSArray *const PLULiteralEscapeTokensStorage = @[@"\\b", @"\\s", @"\"", @"\\w", @"\\.", @"\\|", @"\\*", @"\\)", @"\\("];
#endif

static NSArray *const PLULiteralEscapeTokens = (__bridge NSArray *)(const void *)&PLULiteralEscapeTokensObject;

static const char command_option[] =
    "%s: [command_option] [other_options] file...\n"
    "The file '-' means stdin\n"
    "Command options are (-lint is the default):\n"
    " -help                         show this message and exit\n"
    " -lint                         check the property list files for syntax errors\n"
    " -convert fmt                  rewrite property list files in format\n"
    "                               fmt is one of: xml1 binary1 json swift objc\n"
    "                               note: objc can additionally create a header by adding -header\n"
    " -insert keypath -type value   insert a value into the property list before writing it out\n"
    "                               keypath is a key-value coding key path, with one extension:\n"
    "                               a numerical path component applied to an array will act on the object at that index in the array\n"
    "                               or insert it into the array if the numerical path component is the last one in the key path\n"
    "                               type is one of: bool, integer, float, date, string, data, xml, json\n"
    "                               -bool: YES if passed \"YES\" or \"true\", otherwise NO\n"
    "                               -integer: any valid 64 bit integer\n"
    "                               -float: any valid 64 bit float\n"
    "                               -string: UTF8 encoded string\n"
    "                               -date: a date in XML property list format, not supported if outputting JSON\n"
    "                               -data: a base-64 encoded string\n"
    "                               -xml: an XML property list, useful for inserting compound values\n"
    "                               -json: a JSON fragment, useful for inserting compound values\n"
    "                               -dictionary: inserts an empty dictionary, does not use value\n"
    "                               -array: inserts an empty array, does not use value\n"
    "                               \n"
    "                               optionally, -append may be specified if the keypath references an array to append to the\n"
    "                               end of the array\n"
    "                               value YES, NO, a number, a date, or a base-64 encoded blob of data\n"
    " -replace keypath -type value  same as -insert, but it will overwrite an existing value\n"
    " -remove keypath               removes the value at 'keypath' from the property list before writing it out\n"
    " -extract keypath fmt          outputs the value at 'keypath' in the property list as a new plist of type 'fmt'\n"
    "                               fmt is one of: xml1 binary1 json raw\n"
    "                               an additional \"-expect type\" option can be provided to test that\n"
    "                               the value at the specified keypath is of the specified \"type\", which\n"
    "                               can be one of: bool, integer, float, string, date, data, dictionary, array\n"
    "                               \n"
    "                               when fmt is raw: \n"
    "                                   the following is printed to stdout for each value type:\n"
    "                                       bool: the string \"true\" or \"false\"\n"
    "                                       integer: the numeric value\n"
    "                                       float: the numeric value\n"
    "                                       string: as UTF8-encoded string\n"
    "                                       date: as RFC3339-encoded string in UTC timezone\n"
    "                                       data: as base64-encoded string\n"
    "                                       dictionary: each key on a new line\n"
    "                                       array: the count of items in the array\n"
    "                                   by default, the output is to stdout unless -o is specified\n"
    " -type keypath                 outputs the type of the value at 'keypath' in the property list\n"
    "                               can be one of: bool, integer, float, string, date, data, dictionary, array\n"
    " -create fmt                   creates an empty plist of the specified format\n"
    "                               file may be '-' for stdout\n"
    " -p                            print property list in a human-readable fashion\n"
    "                               (not for machine parsing! this 'format' is not stable)\n"
    "There are some additional optional arguments that apply to the -convert, -insert, -remove, -replace, and -extract verbs:\n"
    " -s                            be silent on success\n"
    " -o path                       specify alternate file path name for result;\n"
    "                               the -o option is used with -convert, and is only\n"
    "                               useful with one file argument (last file overwrites);\n"
    "                               the path '-' means stdout\n"
    " -e extension                  specify alternate extension for converted files\n"
    " -r                            if writing JSON, output in human-readable form\n"
    " -n                            prevent printing a terminating newline if it is not part of the format, such as with raw\n"
    " --                            specifies that all further arguments are file names\n";

static PLUExpectType PLUExpectTypeForObject(id object) {
    if ([object isKindOfClass:[NSNumber class]]) {
        if (object == (__bridge id)kCFBooleanTrue || object == (__bridge id)kCFBooleanFalse) {
            return PLUExpectTypeBool;
        }
        unsigned int type = (unsigned int)(*[(NSNumber *)object objCType] - 'C');
        if (type <= 0x30) {
            if (((1ULL << type) & 0x1424100014241ULL) != 0) {
                return PLUExpectTypeInteger;
            }
            if (((1ULL << type) & 0xA00000000ULL) != 0) {
                return PLUExpectTypeFloat;
            }
        }
        return PLUExpectTypeNone;
    }
    if ([object isKindOfClass:[NSString class]]) {
        return PLUExpectTypeString;
    }
    if ([object isKindOfClass:[NSArray class]]) {
        return PLUExpectTypeArray;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        return PLUExpectTypeDictionary;
    }
    if ([object isKindOfClass:[NSDate class]]) {
        return PLUExpectTypeDate;
    }
    if ([object isKindOfClass:[NSData class]]) {
        return PLUExpectTypeData;
    }
    return PLUExpectTypeNone;
}

static id PLUWrapMutableContainers(id object) {
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSUInteger count = [object count];
        id __unsafe_unretained *objects = count ? (id __unsafe_unretained *)calloc(count, sizeof(id)) : NULL;
        id<NSCopying> __unsafe_unretained *keys = count ? (id<NSCopying> __unsafe_unretained *)calloc(count, sizeof(id<NSCopying>)) : NULL;
        NSMutableArray *convertedObjects = count ? [NSMutableArray arrayWithCapacity:count] : nil;

        [(NSDictionary *)object getObjects:objects andKeys:(id<NSCopying> __unsafe_unretained *)keys count:count];
        for (NSUInteger i = 0; i < count; i++) {
            [convertedObjects addObject:PLUWrapMutableContainers(objects[i])];
        }

        id __unsafe_unretained *convertedBuffer = count ? (id __unsafe_unretained *)calloc(count, sizeof(id)) : NULL;
        for (NSUInteger i = 0; i < count; i++) {
            convertedBuffer[i] = [convertedObjects objectAtIndex:i];
        }

        PLUMutableDictionary *dictionary = [[PLUMutableDictionary alloc]
            initWithObjects:convertedBuffer
                    forKeys:keys
                      count:count];

        free(convertedBuffer);
        free(keys);
        free(objects);
        return dictionary;
    }

    if ([object isKindOfClass:[NSMutableArray class]] || [object isKindOfClass:[NSArray class]]) {
        NSUInteger count = [object count];
        PLUMutableArray *array = [[PLUMutableArray alloc] initWithCapacity:count];
        for (NSUInteger i = 0; i < count; i++) {
            [array addObject:PLUWrapMutableContainers([object objectAtIndex:i])];
        }
        return array;
    }

    return object;
}

static BOOL PLUObjectIsValidForDestinationFormat(id object, PLUOperationFormat destinationFormat) {
    if (destinationFormat == PLUOperationFormatObjC) {
        if ([object isKindOfClass:[NSString class]] || [object isKindOfClass:[NSNumber class]]) {
            return YES;
        }

        if ([object isKindOfClass:[NSArray class]]) {
            for (id value in object) {
                if (!PLUObjectIsValidForDestinationFormat(value, PLUOperationFormatObjC)) {
                    return NO;
                }
            }
            return YES;
        }

        if ([object isKindOfClass:[NSDictionary class]]) {
            __block BOOL valid = YES;
            [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
                if (!PLUObjectIsValidForDestinationFormat(key, PLUOperationFormatObjC) ||
                    !PLUObjectIsValidForDestinationFormat(value, PLUOperationFormatObjC)) {
                    valid = NO;
                    *stop = YES;
                }
            }];
            return valid;
        }

        return NO;
    }

    if (destinationFormat == PLUOperationFormatSwift) {
        return [NSPropertyListSerialization propertyList:object isValidForFormat:NSPropertyListBinaryFormat_v1_0];
    }

    return NO;
}

static id PLUEscapeKeyPathDots(id object) {
    if ([object isKindOfClass:[NSArray class]]) {
        NSUInteger count = [object count];
        for (NSUInteger i = 0; i < count; i++) {
            [object replaceObjectAtIndex:i withObject:PLUEscapeKeyPathDots([object objectAtIndex:i])];
        }
        return object;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        PLUMutableDictionary *dictionary = [PLUMutableDictionary dictionary];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            (void)stop;
            [dictionary setObject:PLUEscapeKeyPathDots(value)
                           forKey:[key stringByReplacingOccurrencesOfString:@"."
                                                                 withString:PLUEscapedDotPlaceholder]];
        }];
        return dictionary;
    }

    return object;
}

static id PLURestoreKeyPathDots(id object) {
    if ([object isKindOfClass:[NSArray class]]) {
        NSUInteger count = [object count];
        for (NSUInteger i = 0; i < count; i++) {
            [object replaceObjectAtIndex:i withObject:PLURestoreKeyPathDots([object objectAtIndex:i])];
        }
        return object;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        PLUMutableDictionary *dictionary = [PLUMutableDictionary dictionary];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            (void)stop;
            [dictionary setObject:PLURestoreKeyPathDots(value)
                           forKey:[key stringByReplacingOccurrencesOfString:PLUEscapedDotPlaceholder
                                                                 withString:@"."]];
        }];
        return dictionary;
    }

    return object;
}

static id PLUCopyDeduplicatedObjectGraph(id object, NSMutableSet *pool) {
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSUInteger count = [object count];
        id __unsafe_unretained *objects = count ? (id __unsafe_unretained *)calloc(count, sizeof(id)) : NULL;
        id<NSCopying> __unsafe_unretained *keys = count ? (id<NSCopying> __unsafe_unretained *)calloc(count, sizeof(id<NSCopying>)) : NULL;
        NSMutableArray *convertedObjects = count ? [NSMutableArray arrayWithCapacity:count] : nil;

        [(NSDictionary *)object getObjects:objects andKeys:(id<NSCopying> __unsafe_unretained *)keys count:count];
        for (NSUInteger i = 0; i < count; i++) {
            [convertedObjects addObject:PLUCopyDeduplicatedObjectGraph(objects[i], pool)];
        }

        id __unsafe_unretained *convertedBuffer = count ? (id __unsafe_unretained *)calloc(count, sizeof(id)) : NULL;
        for (NSUInteger i = 0; i < count; i++) {
            convertedBuffer[i] = [convertedObjects objectAtIndex:i];
        }

        NSDictionary *dictionary = [[NSDictionary alloc]
            initWithObjects:convertedBuffer
                    forKeys:keys
                      count:count];

        free(convertedBuffer);
        free(keys);
        free(objects);
        return dictionary;
    }

    if ([object isKindOfClass:[NSArray class]]) {
        NSUInteger count = [object count];
        NSMutableArray *array = [NSMutableArray arrayWithCapacity:count];
        for (NSUInteger i = 0; i < count; i++) {
            [array addObject:PLUCopyDeduplicatedObjectGraph([object objectAtIndex:i], pool)];
        }
        return [[NSArray alloc] initWithArray:array];
    }

    if ([object isKindOfClass:[NSNumber class]]) {
        return object;
    }

    id member = [pool member:object];
    if (member != nil) {
        return member;
    }

    id copy = [object copy];
    [pool addObject:copy];
    return copy;
}

static NSComparisonResult PLUCompareStrings(id a1, id a2, void *context) {
    (void)context;

    if (!_NSIsNSString(a1) || !_NSIsNSString(a2)) {
        return 0;
    }

    return (NSComparisonResult)[a1 compare:a2
                                   options:577
                                     range:NSMakeRange(0, [a1 length])
                                    locale:[NSLocale systemLocale]];
}

static void PLUAppendObjCDeclarationPreamble(NSMutableString *buffer,
                                             Class rootClass,
                                             BOOL generateHeader,
                                             NSString *inputPath,
                                             NSString *outputPath) {
    NSString *importTarget = nil;
    NSString *importFormat = generateHeader ? @"#import <Foundation/Foundation.h>\n\n" : @"#import \"%@.h\"\n\n";

    if (!generateHeader) {
        importTarget = [[outputPath lastPathComponent] stringByDeletingPathExtension];
    }

    [buffer appendString:[NSString stringWithFormat:importFormat, importTarget]];

    NSString * (^PLUMakeSymbolName)(void) = ^NSString * {
        NSString *symbolBase = [[[[inputPath lastPathComponent] stringByDeletingPathExtension]
            stringByReplacingOccurrencesOfString:@" "
                                      withString:@"_"]
            stringByReplacingOccurrencesOfString:@"-"
                                      withString:@"_"];
        NSMutableCharacterSet *trimSet = [NSMutableCharacterSet symbolCharacterSet];
        [trimSet formUnionWithCharacterSet:[NSCharacterSet controlCharacterSet]];
        return [symbolBase stringByTrimmingCharactersInSet:trimSet];
    };

    NSString *symbolName = PLUMakeSymbolName();
    [buffer appendFormat:@"/// Generated from %@\n", [inputPath lastPathComponent]];
    [buffer appendString:@"__attribute__((visibility(\"hidden\")))\n"];

    if (generateHeader) {
        [buffer appendString:@"extern "];
        [buffer appendFormat:@"%@ * const %@", NSStringFromClass(rootClass), symbolName];
    } else {
        [buffer appendFormat:@"%@ * const %@", NSStringFromClass(rootClass), symbolName];
        [buffer appendString:@" = "];
    }
}

static BOOL PLUAppendObjCRootDeclaration(id object,
                                         NSMutableString *buffer,
                                         BOOL generateHeader,
                                         NSString *inputPath,
                                         NSString *outputPath,
                                         NSError *__strong *error) {
    Class rootClass = Nil;

    if ([object isKindOfClass:[NSString class]]) {
        rootClass = [NSString class];
    } else if ([object isKindOfClass:[NSNumber class]]) {
        rootClass = [NSNumber class];
    } else if ([object isKindOfClass:[NSArray class]]) {
        rootClass = [NSArray class];
    } else if ([object isKindOfClass:[NSDictionary class]]) {
        rootClass = [NSDictionary class];
    }

    if (rootClass != Nil) {
        PLUAppendObjCDeclarationPreamble(buffer, rootClass, generateHeader, inputPath, outputPath);
        return YES;
    }

    if (error == NULL) {
        return NO;
    }

    NSErrorUserInfoKey failureReasonKey = NSLocalizedFailureReasonErrorKey;
    NSString *failureReason = [NSString stringWithFormat:@"Objective-C literal syntax does not support classes of type %@", [object class]];
    *error = [[NSError alloc] initWithDomain:@"com.apple.plutil"
                                        code:-101
                                    userInfo:[NSDictionary dictionaryWithObjects:&failureReason
                                                                         forKeys:&failureReasonKey
                                                                           count:1]];
    return NO;
}

static BOOL PLUSerializeSwiftLiteral(id object,
                                     NSMutableString *buffer,
                                     NSInteger indentLevel,
                                     BOOL shouldIndent,
                                     NSString *inputPath,
                                     NSError *__strong *error) {
    if (indentLevel == 0) {
        BOOL supportsTopLevelType =
            [object isKindOfClass:[NSString class]] ||
            [object isKindOfClass:[NSNumber class]] ||
            [object isKindOfClass:[NSArray class]] ||
            [object isKindOfClass:[NSDictionary class]] ||
            [object isKindOfClass:[NSData class]] ||
            [object isKindOfClass:[NSDate class]];

        if (!supportsTopLevelType) {
            if (error != NULL) {
                NSErrorUserInfoKey failureReasonKey = NSLocalizedFailureReasonErrorKey;
                NSString *failureReason = [NSString stringWithFormat:@"Swift literal syntax does not support classes of type %@", [object class]];
                *error = [[NSError alloc] initWithDomain:@"com.apple.plutil"
                                                    code:-101
                                                userInfo:[NSDictionary dictionaryWithObjects:&failureReason
                                                                                     forKeys:&failureReasonKey
                                                                                       count:1]];
            }
            return NO;
        }

        NSString *symbolName = [[inputPath lastPathComponent] stringByDeletingPathExtension];
        [buffer appendFormat:@"/// Generated from %@\n", [inputPath lastPathComponent]];

        __block Class commonSuperclass = Nil;
        __block NSString *typeSuffix = @"";
        BOOL (^PLUSwiftNeedsAnyTypeForObject)(id) = ^BOOL(id childObject) {
            if (commonSuperclass != Nil && ![childObject isKindOfClass:commonSuperclass]) {
                return YES;
            }

            commonSuperclass = class_getSuperclass([childObject class]);
            return NO;
        };

        if ([object isKindOfClass:[NSDictionary class]]) {
            void (^PLUDetectSwiftDictionaryAnySuffix)(id, id, BOOL *) = ^(id key, id value, BOOL *stop) {
                (void)key;
                if (PLUSwiftNeedsAnyTypeForObject(value)) {
                    typeSuffix = @" : [String : Any]";
                    *stop = YES;
                }
            };
            [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:PLUDetectSwiftDictionaryAnySuffix];
        } else if ([object isKindOfClass:[NSArray class]]) {
            void (^PLUDetectSwiftArrayAnySuffix)(id, NSUInteger, BOOL *) = ^(id value, NSUInteger index, BOOL *stop) {
                (void)index;
                if (PLUSwiftNeedsAnyTypeForObject(value)) {
                    typeSuffix = @" : [Any]";
                    *stop = YES;
                }
            };
            [(NSArray *)object enumerateObjectsUsingBlock:PLUDetectSwiftArrayAnySuffix];
        }

        [buffer appendFormat:@"let %@%@ = ", symbolName, typeSuffix];
    }

    if ([object isKindOfClass:[NSString class]]) {
        if (shouldIndent && indentLevel) {
            for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
                [buffer appendString:@"    "];
            }
        }

        NSString *escapedString = object;
        for (NSString *escapeToken in PLULiteralEscapeTokens) {
            escapedString = [escapedString stringByReplacingOccurrencesOfString:escapeToken
                                                                     withString:[NSString stringWithFormat:@"\\%@", escapeToken]];
        }

        [buffer appendFormat:@"\"%@\"", escapedString];
        return YES;
    }

    if ([object isKindOfClass:[NSNumber class]]) {
        if (shouldIndent && indentLevel) {
            for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
                [buffer appendString:@"    "];
            }
        }

        if (object == (__bridge id)kCFBooleanTrue) {
            [buffer appendString:@"true"];
            return YES;
        }

        if (object == (__bridge id)kCFBooleanFalse) {
            [buffer appendString:@"false"];
            return YES;
        }

        unsigned int numberTypeCode = (unsigned int)(*[(NSNumber *)object objCType] - 'C');
        if (numberTypeCode <= 0x30) {
            if (((1ULL << numberTypeCode) & 0x1424100010241ULL) != 0) {
                [buffer appendFormat:@"%lld", [(NSNumber *)object longLongValue]];
                return YES;
            }

            if (((1ULL << numberTypeCode) & 0xA00000000ULL) != 0) {
                [buffer appendFormat:@"%f", [(NSNumber *)object doubleValue]];
                return YES;
            }

            if (numberTypeCode == 14) {
                [buffer appendFormat:@"%llu", [(NSNumber *)object unsignedLongLongValue]];
                return YES;
            }
        }

        if (error != NULL) {
            NSErrorUserInfoKey failureReasonKey = NSLocalizedFailureReasonErrorKey;
            NSString *failureReason = [NSString stringWithFormat:@"Incorrect numeric type for literal %s", [(NSNumber *)object objCType]];
            *error = [[NSError alloc] initWithDomain:@"com.apple.plutil"
                                                code:-100
                                            userInfo:[NSDictionary dictionaryWithObjects:&failureReason
                                                                                 forKeys:&failureReasonKey
                                                                                   count:1]];
        }
        return NO;
    }

    if ([object isKindOfClass:[NSArray class]]) {
        if (shouldIndent && indentLevel) {
            for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
                [buffer appendString:@"    "];
            }
        }

        [buffer appendString:@"[\n"];
        for (id element in (NSArray *)object) {
            if (!PLUSerializeSwiftLiteral(element, buffer, indentLevel + 1, YES, nil, error)) {
                return NO;
            }
            [buffer appendString:@",\n"];
        }

        if (shouldIndent && indentLevel) {
            for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
                [buffer appendString:@"    "];
            }
        }

        [buffer appendString:@"]"];
        return YES;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSInteger openingIndentCount = shouldIndent;
        NSInteger closingIndentCount = shouldIndent;

        if (shouldIndent && indentLevel) {
            while (openingIndentCount) {
                [buffer appendString:@"    "];
                --openingIndentCount;
            }
        }

        __block BOOL didSerializeDictionary = YES;
        [buffer appendString:@"[\n"];
        NSArray *sortedKeys = [[(NSDictionary *)object allKeys] sortedArrayUsingFunction:PLUCompareStrings context:NULL];
        void (^PLUAppendSwiftDictionaryEntry)(NSString *, NSUInteger, BOOL *) = ^(NSString *key, NSUInteger index, BOOL *stop) {
            (void)index;
            if (!PLUSerializeSwiftLiteral(key, buffer, shouldIndent + 1, YES, nil, error)) {
                *stop = YES;
                didSerializeDictionary = NO;
                return;
            }

            [buffer appendString:@" : "];

            if (!PLUSerializeSwiftLiteral([(NSDictionary *)object objectForKeyedSubscript:key], buffer, shouldIndent + 1, NO, nil, error)) {
                *stop = YES;
                didSerializeDictionary = NO;
                return;
            }

            [buffer appendString:@",\n"];
        };
        [sortedKeys enumerateObjectsUsingBlock:PLUAppendSwiftDictionaryEntry];

        if (shouldIndent) {
            while (closingIndentCount) {
                [buffer appendString:@"    "];
                --closingIndentCount;
            }
        }

        [buffer appendString:@"]"];
        return didSerializeDictionary;
    }

    if ([object isKindOfClass:[NSData class]]) {
        if (shouldIndent && indentLevel) {
            for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
                [buffer appendString:@"    "];
            }
        }

        [buffer appendString:@"Data(bytes: ["];
        const unsigned char *bytes = [(NSData *)object bytes];
        for (NSUInteger byteIndex = 0; byteIndex < [(NSData *)object length]; ++byteIndex) {
            [buffer appendFormat:@"0x%X,", bytes[byteIndex]];
        }
        [buffer appendString:@"])"];
        return YES;
    }

    if ([object isKindOfClass:[NSDate class]]) {
        if (shouldIndent && indentLevel) {
            for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
                [buffer appendString:@"    "];
            }
        }

        [buffer appendFormat:@"Date(timeIntervalSinceReferenceDate: %f)", [(NSDate *)object timeIntervalSinceReferenceDate]];
        return YES;
    }

    if (error != NULL) {
        NSErrorUserInfoKey failureReasonKey = NSLocalizedFailureReasonErrorKey;
        NSString *failureReason = [NSString stringWithFormat:@"Swift literal syntax does not support classes of type %@", [object class]];
        *error = [[NSError alloc] initWithDomain:@"com.apple.plutil"
                                            code:-101
                                        userInfo:[NSDictionary dictionaryWithObjects:&failureReason
                                                                             forKeys:&failureReasonKey
                                                                               count:1]];
    }
    return NO;
}

static BOOL PLUSerializeObjCLiteral(id object,
                                    NSMutableString *buffer,
                                    NSInteger indentLevel,
                                    BOOL shouldIndent,
                                    NSString *inputPath,
                                    NSString *outputPath,
                                    NSError *__strong *error) {
    if (indentLevel == 0 && !PLUAppendObjCRootDeclaration(object, buffer, NO, inputPath, outputPath, error)) {
        return NO;
    }

    if ([object isKindOfClass:[NSString class]]) {
        if (shouldIndent && indentLevel) {
            for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
                [buffer appendString:@"    "];
            }
        }

        NSString *escapedString = object;
        for (NSString *escapeToken in PLULiteralEscapeTokens) {
            escapedString = [escapedString stringByReplacingOccurrencesOfString:escapeToken
                                                                     withString:[NSString stringWithFormat:@"\\%@", escapeToken]];
        }

        [buffer appendFormat:@"@\"%@\"", escapedString];
        return YES;
    }

    if ([object isKindOfClass:[NSNumber class]]) {
        if (shouldIndent && indentLevel) {
            for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
                [buffer appendString:@"    "];
            }
        }

        if (object == (__bridge id)kCFBooleanTrue) {
            [buffer appendString:@"@YES"];
            return YES;
        }

        if (object == (__bridge id)kCFBooleanFalse) {
            [buffer appendString:@"@NO"];
            return YES;
        }

        unsigned int numberTypeCode = (unsigned int)(*[(NSNumber *)object objCType] - 'C');
        if (numberTypeCode <= 0x30) {
            if (((1ULL << numberTypeCode) & 0x1424100010241ULL) != 0) {
                [buffer appendFormat:@"@%lld", [(NSNumber *)object longLongValue]];
                return YES;
            }

            if (((1ULL << numberTypeCode) & 0xA00000000ULL) != 0) {
                [buffer appendFormat:@"@%f", [(NSNumber *)object doubleValue]];
                return YES;
            }

            if (numberTypeCode == 14) {
                [buffer appendFormat:@"@%llu", [(NSNumber *)object unsignedLongLongValue]];
                return YES;
            }
        }

        if (error != NULL) {
            NSErrorUserInfoKey failureReasonKey = NSLocalizedFailureReasonErrorKey;
            NSString *failureReason = [NSString stringWithFormat:@"Incorrect numeric type for literal %s", [(NSNumber *)object objCType]];
            *error = [[NSError alloc] initWithDomain:@"com.apple.plutil"
                                                code:-100
                                            userInfo:[NSDictionary dictionaryWithObjects:&failureReason
                                                                                 forKeys:&failureReasonKey
                                                                                   count:1]];
        }
        return NO;
    }

    if ([object isKindOfClass:[NSArray class]]) {
        if (shouldIndent && indentLevel) {
            for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
                [buffer appendString:@"    "];
            }
        }

        [buffer appendString:@"@[\n"];
        for (id element in (NSArray *)object) {
            if (!PLUSerializeObjCLiteral(element, buffer, indentLevel + 1, YES, nil, nil, error)) {
                return NO;
            }
            [buffer appendString:@",\n"];
        }

        for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
            [buffer appendString:@"    "];
        }

        [buffer appendString:@"]"];
        return YES;
    }

    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error != NULL) {
            NSErrorUserInfoKey failureReasonKey = NSLocalizedFailureReasonErrorKey;
            NSString *failureReason = [NSString stringWithFormat:@"Objective-C literal syntax does not support classes of type %@", [object class]];
            *error = [[NSError alloc] initWithDomain:@"com.apple.plutil"
                                                code:-101
                                            userInfo:[NSDictionary dictionaryWithObjects:&failureReason
                                                                                 forKeys:&failureReasonKey
                                                                                   count:1]];
        }
        return NO;
    }

    if (shouldIndent && indentLevel) {
        for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
            [buffer appendString:@"    "];
        }
    }

    __block BOOL didSerializeDictionary = YES;
    [buffer appendString:@"@{\n"];
    NSArray *sortedKeys = [[(NSDictionary *)object allKeys] sortedArrayUsingFunction:PLUCompareStrings context:NULL];
    void (^PLUAppendObjCDictionaryEntry)(NSString *, NSUInteger, BOOL *) = ^(NSString *a2_, NSUInteger a3_, BOOL *a4_) {
        (void)a3_;
        if (!PLUSerializeObjCLiteral(a2_, buffer, indentLevel + 1, YES, nil, nil, error)) {
            *a4_ = YES;
            didSerializeDictionary = NO;
            return;
        }

        [buffer appendString:@" : "];

        if (!PLUSerializeObjCLiteral([(NSDictionary *)object objectForKeyedSubscript:a2_], buffer, indentLevel + 1, NO, nil, nil, error)) {
            *a4_ = YES;
            didSerializeDictionary = NO;
            return;
        }

        [buffer appendString:@",\n"];
    };
    [sortedKeys enumerateObjectsUsingBlock:PLUAppendObjCDictionaryEntry];

    for (NSInteger indentIndex = indentLevel; indentIndex > 0; --indentIndex) {
        [buffer appendString:@"    "];
    }

    [buffer appendString:@"}"];
    return didSerializeDictionary;
}

static void PLUPrintObject(id obj, NSInteger indent, NSInteger indentStep, int fd) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        dprintf(fd, "{\n");

        NSArray *keys = [[obj allKeys] sortedArrayUsingFunction:PLUCompareStrings context:NULL];
        for (id key in keys) {
            id value = [obj objectForKeyedSubscript:key];

            for (NSInteger i = 0; i < indent; i++)
                dprintf(fd, " ");

            if ([key isKindOfClass:[NSString class]]) {
                dprintf(fd, "\"%s\" => ", [(NSString *)key UTF8String]);
            } else {
                NSString *classDescription = [[[key class] debugDescription] description];
                dprintf(fd, "\"<Error: Not a string: Is a: %s>\" => ", classDescription.UTF8String);
            }

            PLUPrintObject(value, indent + indentStep, indentStep, fd);
        }

        if (indent != indentStep) {
            for (NSInteger i = 0; i < indent - indentStep; i++)
                dprintf(fd, " ");
        }

        dprintf(fd, "}\n");
        return;
    }

    if ([obj isKindOfClass:[NSArray class]]) {
        dprintf(fd, "[\n");

        [(NSArray *)obj enumerateObjectsUsingBlock:^(id entry, NSUInteger idx, BOOL *stop) {
            (void)stop;
            for (NSInteger i = 0; i < indent; i++)
                dprintf(fd, " ");

            dprintf(fd, "%ld => ", (long)idx);
            PLUPrintObject(entry, indent + indentStep, indentStep, fd);
        }];

        if (indent != indentStep) {
            for (NSInteger i = 0; i < indent - indentStep; i++)
                dprintf(fd, " ");
        }

        dprintf(fd, "]\n");
        return;
    }

    if ([obj isKindOfClass:[NSString class]])
        dprintf(fd, "\"%s\"\n", [[obj description] UTF8String]);
    else
        dprintf(fd, "%s\n", [[obj description] UTF8String]);
}

static BOOL PLUContextOperation(PLUContext *context,
                                NSString *format,
                                UInt64 expect,
                                BOOL (^execute)(id plistRoot, id *outValue, NSString **errorString, NSError **error)) {
    NSMutableArray *remainingOptionArgs = [[context remainingOptionArgs] mutableCopy];
    PLUOperationFormat operationFormat = 0;
    BOOL prettyJSON = NO;
    BOOL preserveInputFormat = NO;
    NSString *explicitOutputPath = nil;
    NSString *outputExtension = nil;
    BOOL appendTrailingNewline = YES;

    if ([format isEqual:@"binary1"]) {
        operationFormat = PLUOperationFormatBinary1;
    } else if ([format isEqual:@"xml1"]) {
        operationFormat = PLUOperationFormatXML1;
    } else if ([format isEqual:@"json"]) {
        operationFormat = PLUOperationFormatJSON;
    } else if ([format isEqual:@"swift"]) {
        operationFormat = PLUOperationFormatSwift;
    } else if ([format isEqual:@"objc"]) {
        operationFormat = PLUOperationFormatObjC;
    } else if ([format isEqual:@"NoConversion"]) {
        preserveInputFormat = YES;
        operationFormat = PLUOperationFormatNoConversion;
    } else if ([format isEqual:@"raw"]) {
        operationFormat = PLUOperationFormatRaw;
    } else if ([format isEqual:@"type"]) {
        operationFormat = PLUOperationFormatType;
    } else {
        dprintf(context.errorFileHandle.fileDescriptor, "Unknown format specifier: %s\n", format.UTF8String);
        dprintf(context.errorFileHandle.fileDescriptor, command_option, *_CFGetProgname());
    }

    NSUInteger optionCount = [remainingOptionArgs count];
    if (optionCount >= 1) {
        for (NSUInteger optionIndex = 0; optionIndex < optionCount; ++optionIndex) {
            NSString *option = [remainingOptionArgs objectAtIndex:optionIndex];

            if ([@"--" isEqual:option]) {
                [remainingOptionArgs removeObjectAtIndex:optionIndex];
                break;
            }

            if ([@"-n" isEqual:option]) {
                appendTrailingNewline = NO;
                [remainingOptionArgs removeObjectAtIndex:optionIndex--];
                --optionCount;
                continue;
            }

            if ([@"-s" isEqual:option]) {
                [remainingOptionArgs removeObjectAtIndex:optionIndex--];
                --optionCount;
                continue;
            }

            if ([@"-r" isEqual:option]) {
                prettyJSON = YES;
                [remainingOptionArgs removeObjectAtIndex:optionIndex--];
                --optionCount;
                continue;
            }

            if ([@"-o" isEqual:option]) {
                if ([remainingOptionArgs count] < optionIndex + 2) {
                    dprintf(context.errorFileHandle.fileDescriptor, "Missing argument for -o.\n");
                    dprintf(context.errorFileHandle.fileDescriptor, command_option, *_CFGetProgname());
                    return NO;
                }

                explicitOutputPath = [remainingOptionArgs objectAtIndex:optionIndex + 1];
                [remainingOptionArgs removeObjectAtIndex:optionIndex];
                [remainingOptionArgs removeObjectAtIndex:optionIndex--];
                optionCount -= 2;
                continue;
            }

            if ([@"-e" isEqual:option]) {
                if ([remainingOptionArgs count] < optionIndex + 2) {
                    dprintf(context.errorFileHandle.fileDescriptor, "Missing argument for -e.\n");
                    dprintf(context.errorFileHandle.fileDescriptor, command_option, *_CFGetProgname());
                    return NO;
                }

                outputExtension = [remainingOptionArgs objectAtIndex:optionIndex + 1];
                [remainingOptionArgs removeObjectAtIndex:optionIndex];
                [remainingOptionArgs removeObjectAtIndex:optionIndex--];
                optionCount -= 2;
                continue;
            }

            if ([option hasPrefix:@"-"] && [option length] >= 2) {
                dprintf(context.errorFileHandle.fileDescriptor, "unrecognized option: %s\n", option.UTF8String);
                dprintf(context.errorFileHandle.fileDescriptor, command_option, *_CFGetProgname());
                return NO;
            }
        }
    }

    if (![remainingOptionArgs count]) {
        dprintf(context.errorFileHandle.fileDescriptor, "No files specified.\n");
        dprintf(context.errorFileHandle.fileDescriptor, command_option, *_CFGetProgname());
        return NO;
    }

    NSJSONWritingOptions jsonWritingOptions = prettyJSON ? 3 : 0;
    BOOL encounteredError = NO;
    NSString *debugDescriptionKey = (__bridge NSString *)kCFErrorDebugDescriptionKey;

    for (NSUInteger fileIndex = 0; fileIndex < [remainingOptionArgs count]; ++fileIndex) {
        NSError *operationError = nil;
        NSPropertyListFormat propertyListFormat = 0;
        NSString *displayPath = [remainingOptionArgs objectAtIndex:fileIndex];
        NSString *requestedOutputPath = explicitOutputPath;
        id parsedObject = nil;

        if (context.command == PLUCommandCreate) {
            propertyListFormat = NSPropertyListXMLFormat_v1_0;
            if (preserveInputFormat) {
                operationFormat = PLUOperationFormatXML1;
            }
            requestedOutputPath = displayPath;
            parsedObject = @{};
        } else {
            NSData *inputData = nil;

            if ([displayPath isEqual:@"-"]) {
                inputData = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
                if (inputData == nil) {
                    dprintf(context.outputFileHandle.fileDescriptor, "Unable to read file from standard input");
                    encounteredError = YES;
                    continue;
                }
                displayPath = @"<stdin>";
            } else if (![displayPath length] ||
                       (inputData = [NSData dataWithContentsOfFile:displayPath options:1 error:&operationError]) == nil) {
                dprintf(context.outputFileHandle.fileDescriptor,
                        "%s: file does not exist or is not readable or is not a regular file (%s)\n",
                        displayPath.UTF8String,
                        [[operationError description] UTF8String]);
                encounteredError = YES;
                continue;
            }

            parsedObject = [NSPropertyListSerialization propertyListWithData:inputData
                                                                     options:(execute != nil ? NSPropertyListMutableContainers : 0)
                                                                      format:&propertyListFormat
                                                                       error:&operationError];
            if (parsedObject != nil) {
                if (preserveInputFormat) {
                    operationFormat = (PLUOperationFormat)propertyListFormat;
                }
            } else {
                NSError *jsonError = nil;
                parsedObject = [NSJSONSerialization JSONObjectWithData:inputData
                                                               options:(NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves)
                                                                 error:&jsonError];
                if (parsedObject != nil) {
                    if (preserveInputFormat) {
                        operationFormat = PLUOperationFormatJSON;
                    }
                } else {
                    NSString *plistErrorDescription = operationError ? ([[operationError userInfo] objectForKeyedSubscript:debugDescriptionKey] ?: @"<unknown error>") : @"<unknown error>";
                    NSString *jsonErrorDescription = jsonError ? ([[jsonError userInfo] objectForKeyedSubscript:debugDescriptionKey] ?: @"<unknown error>") : @"<unknown error>";
                    dprintf(context.outputFileHandle.fileDescriptor,
                            "%s: Property List error: %s / JSON error: %s\n",
                            displayPath.UTF8String,
                            plistErrorDescription.UTF8String,
                            jsonErrorDescription.UTF8String);
                    encounteredError = YES;
                    continue;
                }
            }
        }

        id mutableObject = PLUWrapMutableContainers(parsedObject);
        if (mutableObject == nil) {
            dprintf(context.errorFileHandle.fileDescriptor,
                    "%s: dictionaries are required to have string keys in property lists\n",
                    displayPath.UTF8String);
            encounteredError = YES;
            continue;
        }

        if (operationFormat == PLUOperationFormatBinary1 || operationFormat == PLUOperationFormatXML1) {
            if (![NSPropertyListSerialization propertyList:mutableObject isValidForFormat:(NSPropertyListFormat)operationFormat]) {
                dprintf(context.outputFileHandle.fileDescriptor,
                        "%s: invalid object in plist for destination format\n",
                        displayPath.UTF8String);
                encounteredError = YES;
                continue;
            }
        } else if (operationFormat == PLUOperationFormatSwift || operationFormat == PLUOperationFormatObjC) {
            if (!PLUObjectIsValidForDestinationFormat(mutableObject, operationFormat)) {
                dprintf(context.outputFileHandle.fileDescriptor,
                        "%s: invalid object in plist for destination format\n",
                        displayPath.UTF8String);
                if (operationFormat == PLUOperationFormatObjC) {
                    dprintf(context.outputFileHandle.fileDescriptor,
                            "%s contains an object that cannot be represented in Obj-C literal syntax\n",
                            displayPath.UTF8String);
                }
                encounteredError = YES;
                continue;
            }
        } else if (operationFormat == PLUOperationFormatJSON && ![NSJSONSerialization isValidJSONObject:mutableObject]) {
            dprintf(context.outputFileHandle.fileDescriptor,
                    "%s: invalid object in plist for destination format\n",
                    displayPath.UTF8String);
            encounteredError = YES;
            continue;
        }

        id transformedObject = mutableObject;
        if (execute != nil) {
            id escapedMutationRoot = PLUEscapeKeyPathDots(mutableObject);
            id replacementValue = nil;
            NSString *operationErrorString = nil;
            NSError *mutationError = nil;

            if (execute(escapedMutationRoot, &replacementValue, &operationErrorString, &mutationError)) {
                transformedObject = PLURestoreKeyPathDots(replacementValue ?: escapedMutationRoot);
            } else {
                NSString *mutationErrorDescription = mutationError ? ([[mutationError userInfo] objectForKeyedSubscript:debugDescriptionKey] ?: @"<unknown error>") : @"<unknown error>";
                dprintf(context.outputFileHandle.fileDescriptor,
                        "%s: %s, error: %s\n",
                        displayPath.UTF8String,
                        operationErrorString.UTF8String,
                        mutationErrorDescription.UTF8String);
                encounteredError = YES;
                continue;
            }
        }

        PLUExpectType actualType = PLUExpectTypeForObject(transformedObject);
        if (operationFormat == PLUOperationFormatRaw &&
            ![transformedObject isKindOfClass:[NSString class]] &&
            ![transformedObject isKindOfClass:[NSNumber class]] &&
            ![transformedObject isKindOfClass:[NSDate class]] &&
            ![transformedObject isKindOfClass:[NSData class]] &&
            ![transformedObject isKindOfClass:[NSDictionary class]] &&
            ![transformedObject isKindOfClass:[NSArray class]]) {
            dprintf(context.errorFileHandle.fileDescriptor,
                    "%s: value at [%s] is a %s type and cannot be extracted in raw format\n",
                    displayPath.UTF8String,
                    context.keyPath.UTF8String,
                    [PLUExpectedTypeNames[actualType] UTF8String]);
            encounteredError = YES;
            continue;
        }

        if (expect != 0 && actualType != expect) {
            dprintf(context.errorFileHandle.fileDescriptor,
                    "%s: value at [%s] expected to be %s but is a %s\n",
                    displayPath.UTF8String,
                    context.keyPath.UTF8String,
                    [PLUExpectedTypeNames[expect] UTF8String],
                    [PLUExpectedTypeNames[actualType] UTF8String]);
            encounteredError = YES;
            continue;
        }

        if (execute != nil) {
            NSMutableSet *copyPool = [NSMutableSet new];
            transformedObject = PLUCopyDeduplicatedObjectGraph(transformedObject, copyPool);
        }

        NSString * (^PLUResolveOutputPath)(void) = ^NSString * {
            if (requestedOutputPath != nil) {
                return requestedOutputPath;
            }

            if (outputExtension != nil) {
                return [[displayPath stringByDeletingPathExtension] stringByAppendingPathExtension:outputExtension];
            }

            if (operationFormat == PLUOperationFormatSwift) {
                return [[displayPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"swift"];
            }

            if (operationFormat == PLUOperationFormatObjC) {
                return [[displayPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m"];
            }

            return displayPath;
        };
        NSString *resolvedOutputPath = PLUResolveOutputPath();

        NSData *serializedData = nil;
        operationError = nil;

        if (operationFormat == PLUOperationFormatXML1 || operationFormat == PLUOperationFormatBinary1) {
            serializedData = [NSPropertyListSerialization dataWithPropertyList:transformedObject
                                                                        format:(NSPropertyListFormat)operationFormat
                                                                       options:0
                                                                         error:&operationError];
        } else {
            switch (operationFormat) {
            case PLUOperationFormatJSON:
                if ([NSJSONSerialization isValidJSONObject:transformedObject]) {
                    serializedData = [NSJSONSerialization dataWithJSONObject:transformedObject
                                                                     options:jsonWritingOptions
                                                                       error:&operationError];
                } else {
                    dprintf(context.outputFileHandle.fileDescriptor,
                            "%s: invalid object in plist for JSON format\n",
                            displayPath.UTF8String);
                    encounteredError = YES;
                    continue;
                }
                break;
            case PLUOperationFormatSwift: {
                NSMutableString *swiftBuffer = [NSMutableString new];
                if (PLUSerializeSwiftLiteral(transformedObject, swiftBuffer, 0, YES, displayPath, &operationError)) {
                    serializedData = [swiftBuffer dataUsingEncoding:NSUTF8StringEncoding];
                }
                break;
            }
            case PLUOperationFormatObjC: {
                NSMutableString *objcBuffer = [NSMutableString new];
                if (PLUSerializeObjCLiteral(transformedObject, objcBuffer, 0, YES, displayPath, resolvedOutputPath, &operationError)) {
                    [objcBuffer appendString:@";\n"];
                    serializedData = [objcBuffer dataUsingEncoding:NSUTF8StringEncoding];
                }
                break;
            }
            case PLUOperationFormatRaw: {
                NSMutableString *rawBuffer = [NSMutableString new];

                if ([transformedObject isKindOfClass:[NSString class]]) {
                    [rawBuffer appendString:transformedObject];
                } else if ([transformedObject isKindOfClass:[NSNumber class]]) {
                    if (transformedObject == (__bridge id)kCFBooleanTrue) {
                        [rawBuffer appendString:@"true"];
                    } else if (transformedObject == (__bridge id)kCFBooleanFalse) {
                        [rawBuffer appendString:@"false"];
                    } else {
                        unsigned int numberTypeCode = (unsigned int)(*[(NSNumber *)transformedObject objCType] - 'C');
                        if (numberTypeCode <= 0x30 && ((1ULL << numberTypeCode) & 0x1424100010241ULL) != 0) {
                            [rawBuffer appendFormat:@"%lld", [(NSNumber *)transformedObject longLongValue]];
                        } else if (numberTypeCode <= 0x30 && ((1ULL << numberTypeCode) & 0xA00000000ULL) != 0) {
                            [rawBuffer appendFormat:@"%f", [(NSNumber *)transformedObject doubleValue]];
                        } else if (numberTypeCode == 14) {
                            [rawBuffer appendFormat:@"%llu", [(NSNumber *)transformedObject unsignedLongLongValue]];
                        } else {
                            NSErrorUserInfoKey failureReasonKey = NSLocalizedFailureReasonErrorKey;
                            NSString *failureReason = [NSString stringWithFormat:@"Incorrect numeric type for literal %s", [(NSNumber *)transformedObject objCType]];
                            operationError = [[NSError alloc] initWithDomain:@"com.apple.plutil"
                                                                        code:-100
                                                                    userInfo:[NSDictionary dictionaryWithObjects:&failureReason
                                                                                                         forKeys:&failureReasonKey
                                                                                                           count:1]];
                        }
                    }
                } else if ([transformedObject isKindOfClass:[NSData class]]) {
                    [rawBuffer appendString:[(NSData *)transformedObject base64EncodedStringWithOptions:0]];
                } else if ([transformedObject isKindOfClass:[NSDate class]]) {
                    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
                    [formatter setFormatOptions:1907];
                    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
                    [rawBuffer appendString:[formatter stringFromDate:transformedObject]];
                } else if ([transformedObject isKindOfClass:[NSDictionary class]]) {
                    NSArray *sortedKeys = [[(NSDictionary *)transformedObject allKeys] sortedArrayUsingFunction:PLUCompareStrings context:NULL];
                    NSUInteger keyCount = [sortedKeys count];
                    void (^PLUAppendRawDictionaryKey)(NSString *, NSUInteger, BOOL *) = ^(NSString *a2, NSUInteger a3, BOOL *a4) {
                        (void)a4;
                        [rawBuffer appendString:a2];
                        if (keyCount - 1 > a3) {
                            [rawBuffer appendString:@"\n"];
                        }
                    };
                    [sortedKeys enumerateObjectsUsingBlock:PLUAppendRawDictionaryKey];
                } else if ([transformedObject isKindOfClass:[NSArray class]]) {
                    [rawBuffer appendFormat:@"%lu", (unsigned long)[(NSArray *)transformedObject count]];
                } else {
                    NSErrorUserInfoKey failureReasonKey = NSLocalizedFailureReasonErrorKey;
                    NSString *failureReason = [NSString stringWithFormat:@"Raw syntax does not support classes of type %@", [transformedObject class]];
                    operationError = [[NSError alloc] initWithDomain:@"com.apple.plutil"
                                                                code:-101
                                                            userInfo:[NSDictionary dictionaryWithObjects:&failureReason
                                                                                                 forKeys:&failureReasonKey
                                                                                                   count:1]];
                }

                if (operationError == nil) {
                    serializedData = [rawBuffer dataUsingEncoding:NSUTF8StringEncoding];
                }
                break;
            }
            default:
                if (operationFormat == PLUOperationFormatType) {
                    NSString *typeName = [PLUExpectedTypeNames[PLUExpectTypeForObject(transformedObject)] copy];
                    serializedData = [typeName dataUsingEncoding:NSUTF8StringEncoding];
                }
                break;
            }
        }

        if (serializedData == nil) {
            NSString *serializationErrorDescription = operationError ? ([[operationError userInfo] objectForKeyedSubscript:debugDescriptionKey] ?: @"<unknown error>") : @"<unknown error>";
            dprintf(context.outputFileHandle.fileDescriptor, "%s: %s\n", displayPath.UTF8String, serializationErrorDescription.UTF8String);
            encounteredError = YES;
            continue;
        }

        BOOL wroteOutput = NO;
        BOOL wroteToFile = NO;
        if (requestedOutputPath != nil) {
            if ([requestedOutputPath isEqual:@"-"]) {
                ssize_t bytesWritten = write(context.outputFileHandle.fileDescriptor, [serializedData bytes], [serializedData length]);
                wroteOutput = bytesWritten == (ssize_t)[serializedData length];
                if (appendTrailingNewline &&
                    (operationFormat == PLUOperationFormatType || operationFormat == PLUOperationFormatRaw)) {
                    dprintf(context.outputFileHandle.fileDescriptor, "\n");
                }
            } else {
                wroteToFile = YES;
                wroteOutput = [serializedData writeToFile:resolvedOutputPath atomically:NO];
            }
        } else if (operationFormat == PLUOperationFormatType || operationFormat == PLUOperationFormatRaw) {
            ssize_t bytesWritten = write(context.outputFileHandle.fileDescriptor, [serializedData bytes], [serializedData length]);
            wroteOutput = bytesWritten == (ssize_t)[serializedData length];
            if (appendTrailingNewline) {
                dprintf(context.outputFileHandle.fileDescriptor, "\n");
            }
        } else {
            wroteToFile = YES;
            wroteOutput = [serializedData writeToFile:resolvedOutputPath atomically:NO];
        }

        if (wroteOutput &&
            wroteToFile &&
            operationFormat == PLUOperationFormatObjC &&
            context.command == PLUCommandConvertWithHeader) {
            NSMutableString *headerBuffer = [NSMutableString string];
            if (!PLUAppendObjCRootDeclaration(transformedObject, headerBuffer, YES, displayPath, resolvedOutputPath, &operationError) ||
                (([headerBuffer appendString:@";\n"]), ((serializedData = [headerBuffer dataUsingEncoding:NSUTF8StringEncoding]) == nil))) {
                NSString *headerErrorDescription = operationError ? ([[operationError userInfo] objectForKeyedSubscript:debugDescriptionKey] ?: @"<unknown error>") : @"<unknown error>";
                dprintf(context.outputFileHandle.fileDescriptor, "%s: %s\n", displayPath.UTF8String, headerErrorDescription.UTF8String);
                encounteredError = YES;
                continue;
            }
            wroteOutput = [serializedData writeToFile:[[resolvedOutputPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"h"]
                                           atomically:NO];
        }

        if (!wroteOutput) {
            dprintf(context.outputFileHandle.fileDescriptor, "%s: %s\n", resolvedOutputPath.UTF8String, strerror(errno));
            encounteredError = YES;
        }
    }

    return !encounteredError;
}

@implementation PLUContext

+ (PLUContext *)contextWithArguments:(NSArray *)arguments
                    outputFileHandle:(NSFileHandle *)outputFileHandle
                     errorFileHandle:(NSFileHandle *)errorFileHandle {
    PLUContext *context = [[self alloc] init];
    NSAssert(context, @"`context` should not be `nil`");

    context.initalArguments = arguments;
    context.command = 0;
    context.outputFileHandle = outputFileHandle;
    context.errorFileHandle = errorFileHandle;

    return context;
}

- (BOOL)create {
    return PLUContextOperation(self, self->_format, 0, nil);
}

- (BOOL)convert {
    return PLUContextOperation(self, self->_format, 0, nil);
}

- (BOOL)execute {
    if (![self processInitialArgs]) {
        return NO;
    }

    switch ((PLUCommand)self->_command) {
    case PLUCommandLint:
        return [self lint];
    case PLUCommandHelp:
        dprintf(self.outputFileHandle.fileDescriptor, command_option, *_CFGetProgname());
        return YES;
    case PLUCommandConvert:
    case PLUCommandConvertWithHeader:
        return [self convert];
    case PLUCommandInsert:
    case PLUCommandReplace: {
        BOOL override = self->_command == PLUCommandReplace;
        NSString *keyPath = [self.keyPath stringByReplacingOccurrencesOfString:@"\\."
                                                                    withString:PLUEscapedDotPlaceholder];
        NSString *unparsedValue = self.unparsedValue;
        NSString *type = self.type;
        __block id parsedValue = nil;

        if ([type isEqualToString:@"-bool"]) {
            if ([unparsedValue caseInsensitiveCompare:@"YES"] && [unparsedValue caseInsensitiveCompare:@"true"]) {
                parsedValue = [NSNumber numberWithBool:NO];
            } else {
                parsedValue = [NSNumber numberWithBool:YES];
            }
        } else if ([type isEqualToString:@"-integer"]) {
            parsedValue = [NSNumber numberWithInteger:[unparsedValue integerValue]];
        } else if ([type isEqualToString:@"-date"]) {
            NSDictionary *data = [NSPropertyListSerialization propertyListWithData:
                                                                  [[NSString stringWithFormat:
                                                                                 @"<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>value</key><date>%@</date></dict></plist>",
                                                                                 unparsedValue]
                                                                      dataUsingEncoding:NSUTF8StringEncoding]
                                                                           options:0
                                                                            format:nil
                                                                             error:nil];
            if (data) {
                parsedValue = [data objectForKey:@"value"];
            }
        } else if ([type isEqualToString:@"-data"]) {
            parsedValue = [[NSData alloc] initWithBase64EncodedString:unparsedValue options:1];
        } else if ([type isEqualToString:@"-float"]) {
            parsedValue = [NSNumber numberWithDouble:[unparsedValue doubleValue]];
        } else if ([type isEqualToString:@"-xml"]) {
            parsedValue = [NSPropertyListSerialization propertyListWithData:[unparsedValue dataUsingEncoding:NSUTF8StringEncoding]
                                                                    options:NSPropertyListMutableContainersAndLeaves
                                                                     format:nil
                                                                      error:nil];
        } else if ([type isEqualToString:@"-json"]) {
            parsedValue = [NSJSONSerialization JSONObjectWithData:[unparsedValue dataUsingEncoding:NSUTF8StringEncoding]
                                                          options:(NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves | NSJSONReadingFragmentsAllowed)
                                                            error:nil];
        } else if ([type isEqualToString:@"-string"]) {
            parsedValue = unparsedValue;
        } else if ([type isEqualToString:@"-dictionary"]) {
            parsedValue = @{};
        } else if ([type isEqualToString:@"-array"]) {
            parsedValue = @[];
        }

        return PLUContextOperation(self, @"NoConversion", 0, ^BOOL(id plistRoot, id *outValue, NSString **errorString, NSError **error) {
            (void)outValue;
            NSString *desc = nil;
            *errorString = @"Could not modify plist";

            if (!parsedValue) {
                desc = [NSString stringWithFormat:@"Failed to parse value %@ with type %@", unparsedValue, type];
            } else if (![plistRoot validateValue:&parsedValue forKeyPath:keyPath error:error]) {
                desc = [NSString stringWithFormat:@"Value %@ not valid for key path %@", unparsedValue, keyPath];
            } else {
                NSString *lastComponent = [[keyPath componentsSeparatedByString:@"."] lastObject];
                if ([lastComponent integerValue] || [lastComponent isEqualToString:@"0"]) {
                    NSString *containerPath = keyPath;
                    if (![self append]) {
                        containerPath = [keyPath substringToIndex:[keyPath length] - [lastComponent length] - 1];
                    }

                    id container = [plistRoot valueForKeyPath:containerPath];
                    if ([container isKindOfClass:[NSArray class]]) {
                        if ([self append]) {
                            [container addObject:parsedValue];
                        } else {
                            [container insertObject:parsedValue atIndex:[lastComponent integerValue]];
                        }
                        return YES;
                    }

                    desc = [NSString stringWithFormat:@"No array found at key path %@ to insert into", containerPath];
                } else {
                    id existingValue = [plistRoot valueForKeyPath:keyPath];
                    if ([existingValue isKindOfClass:[NSArray class]] && [self append]) {
                        [existingValue addObject:parsedValue];
                        return YES;
                    }

                    if (!override && existingValue) {
                        desc = [NSString stringWithFormat:@"Value %@ already exists at key path %@", existingValue, keyPath];
                    } else {
                        [plistRoot setValue:parsedValue forKeyPath:keyPath];
                        return YES;
                    }
                }
            }

            if (error) {
                *error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain
                                                    code:1024
                                                userInfo:@{(__bridge NSString *)kCFErrorDebugDescriptionKey : desc}];
            }
            return NO;
        });
    }
    case PLUCommandRemove: {
        NSString *keyPath = [self.keyPath stringByReplacingOccurrencesOfString:@"\\."
                                                                    withString:PLUEscapedDotPlaceholder];
        return PLUContextOperation(self, @"NoConversion", 0, ^BOOL(id plistRoot, id *outValue, NSString **errorString, NSError **error) {
            (void)outValue;
            id value = [plistRoot valueForKeyPath:keyPath];

            if (value) {
                [plistRoot setValue:nil forKeyPath:keyPath];
                return YES;
            }

            if (error) {
                NSString *desc = [NSString stringWithFormat:@"No value to remove at key path %@", keyPath];
                *error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain
                                                    code:1024
                                                userInfo:@{(__bridge NSString *)kCFErrorDebugDescriptionKey : desc}];
            }
            *errorString = @"Could not modify plist";
            return NO;
        });
    }
    case PLUCommandExtract: {
        NSString *keyPath = [self.keyPath stringByReplacingOccurrencesOfString:@"\\."
                                                                    withString:PLUEscapedDotPlaceholder];
        return PLUContextOperation(self, self->_format, self->_expect, ^BOOL(id plistRoot, id *outValue, NSString **errorString, NSError **error) {
            id value = [plistRoot valueForKeyPath:keyPath];

            if (value) {
                *outValue = value;
                return YES;
            }

            if (error) {
                NSString *desc = [NSString stringWithFormat:@"No value at that key path or invalid key path: %@", keyPath];
                *error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain
                                                    code:1024
                                                userInfo:@{(__bridge NSString *)kCFErrorDebugDescriptionKey : desc}];
            }
            *errorString = @"Could not extract value";
            return NO;
        });
    }
    case PLUCommandPrint:
        return [self print];
    case PLUCommandType: {
        NSString *keyPath = [self.keyPath stringByReplacingOccurrencesOfString:@"\\."
                                                                    withString:PLUEscapedDotPlaceholder];
        return PLUContextOperation(self, @"type", self->_expect, ^BOOL(id plistRoot, id *outValue, NSString **errorString, NSError **error) {
            id value = [plistRoot valueForKeyPath:keyPath];

            if (value) {
                *outValue = value;
                return YES;
            }

            if (error) {
                NSString *desc = [NSString stringWithFormat:@"No value at that key path or invalid key path: %@", keyPath];
                *error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain
                                                    code:1024
                                                userInfo:@{(__bridge NSString *)kCFErrorDebugDescriptionKey : desc}];
            }
            *errorString = @"Could not extract value";
            return NO;
        });
    }
    case PLUCommandCreate:
        return [self create];
    default:
        return (BOOL)self;
    }
}

- (BOOL)lint {
    NSMutableArray *args = [self->_remainingOptionArgs mutableCopy];
    BOOL silent = NO;
    BOOL hadOptionError = NO;

    for (NSUInteger i = 0; i < args.count;) {
        NSString *arg = [args objectAtIndex:i];

        if ([@"--" isEqual:arg]) {
            [args removeObjectAtIndex:i];
            break;
        }

        if ([@"-s" isEqual:arg]) {
            [args removeObjectAtIndex:i--];
            silent = YES;
        } else if ([@"-o" isEqual:arg]) {
            dprintf(self->_errorFileHandle.fileDescriptor, "-o is not used with -lint.\n");
            hadOptionError = YES;
        } else if ([@"-e" isEqual:arg]) {
            dprintf(self->_errorFileHandle.fileDescriptor, "-e is not used with -lint.\n");
            hadOptionError = YES;
        } else if ([arg hasPrefix:@"-"] && [arg length] >= 2) {
            dprintf(self->_errorFileHandle.fileDescriptor, "unrecognized option: %s\n", arg.UTF8String);
            hadOptionError = YES;
        } else {
            break;
        }

        i++;
    }

    if (!args.count) {
        dprintf(self->_errorFileHandle.fileDescriptor, "No files specified.\n");
        return NO;
    }

    if (hadOptionError) {
        return NO;
    }

    BOOL success = YES;
    for (NSString *path in args) {
        NSString *displayPath = path;
        NSData *data = nil;
        NSError *error = nil;

        if ([path isEqual:@"-"]) {
            data = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
            if (!data) {
                dprintf(self->_outputFileHandle.fileDescriptor, "Unable to read file from standard input");
                success = NO;
                continue;
            }
            displayPath = @"<stdin>";
        } else if (![path length] ||
                   (data = [NSData dataWithContentsOfFile:path options:1 error:&error]) == nil) {
            dprintf(self->_outputFileHandle.fileDescriptor,
                    "%s: file does not exist or is not readable or is not a regular file (%s)\n",
                    path.UTF8String,
                    [[error description] UTF8String]);
            success = NO;
            continue;
        }

        error = nil;
        if ([NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:&error]) {
            if (!silent) {
                dprintf(self->_outputFileHandle.fileDescriptor, "%s: OK\n", displayPath.UTF8String);
            }
        } else {
            NSString *detail = error ? ([error.userInfo valueForKey:(__bridge NSString *)kCFErrorDebugDescriptionKey] ?: @"<unknown error>") : @"<unknown error>";
            dprintf(self->_outputFileHandle.fileDescriptor, "%s: %s\n", displayPath.UTF8String, detail.UTF8String);
            success = NO;
        }
    }

    return success;
}

- (BOOL)print {
    NSMutableArray *args = [[self remainingOptionArgs] mutableCopy];
    NSUInteger count = args.count;
    NSUInteger i = 0;

    while (count >= 1) {
        NSString *arg = [args objectAtIndex:i];

        if ([@"--" isEqual:arg]) {
            [args removeObjectAtIndex:i];
            break;
        }

        if ([@"-s" isEqual:arg]) {
            dprintf(self->_errorFileHandle.fileDescriptor, "-s doesn't make a lot of sense with -p.\n");
            [args removeObjectAtIndex:i--];
            count--;
        } else if ([@"-o" isEqual:arg]) {
            dprintf(self->_errorFileHandle.fileDescriptor, "-o is not used with -p.\n");
            goto usage;
        } else if ([@"-e" isEqual:arg]) {
            dprintf(self->_errorFileHandle.fileDescriptor, "-e is not used with -p.\n");
            goto usage;
        } else if ([arg hasPrefix:@"-"] && [arg length] >= 2) {
            dprintf(self->_errorFileHandle.fileDescriptor, "unrecognized option: %s\n", arg.UTF8String);
            goto usage;
        } else {
            break;
        }

        if (++i >= count) {
            break;
        }
    }

    if (!args.count) {
        dprintf(self->_errorFileHandle.fileDescriptor, "No files specified.\n");
        goto usage;
    }

    count = args.count;
    i = 0;
    BOOL hadError = NO;

    while (i < count) {
        NSString *file = [args objectAtIndex:i];
        NSString *displayName = file;
        NSData *data = nil;
        NSError *error = nil;
        id plist = nil;

        if ([file isEqual:@"-"]) {
            data = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
            if (!data) {
                dprintf(self->_errorFileHandle.fileDescriptor, "Unable to read file from standard input\n");
                hadError = YES;
                goto next_file;
            }
            displayName = @"<stdin>";
        } else if (![file length] ||
                   (data = [NSData dataWithContentsOfFile:file options:1 error:&error]) == nil) {
            NSString *message = [NSString stringWithFormat:@"%@: file does not exist or is not readable or is not a regular file (%@)\n",
                                                           file,
                                                           [error description]];
            dprintf(self->_outputFileHandle.fileDescriptor, "%s", message.UTF8String);
            hadError = YES;
            goto next_file;
        }

        Boolean executableOrLibraryType = false;
        CFDictionaryRef info = _CFBundleCopyInfoDictionaryForExecutableFileData((__bridge CFDataRef)data, &executableOrLibraryType);
        if (info) {
            PLUPrintObject((__bridge id)info, 2, 2, self->_outputFileHandle.fileDescriptor);
            CFRelease(info);
            goto next_file;
        }

        if (executableOrLibraryType) {
            NSString *message = [NSString stringWithFormat:@"%@: file was executable or library type but did not contain an embedded Info.plist\n",
                                                           displayName];
            dprintf(self->_outputFileHandle.fileDescriptor, "%s", message.UTF8String);
            hadError = YES;
            goto next_file;
        }

        plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:&error];
        if (plist) {
            PLUPrintObject(plist, 2, 2, self->_outputFileHandle.fileDescriptor);
        } else {
            NSString *detail = error ? ([error.userInfo valueForKey:(__bridge NSString *)kCFErrorDebugDescriptionKey] ?: @"<unknown error>") : @"<unknown error>";
            dprintf(self->_outputFileHandle.fileDescriptor, "%s: %s\n", displayName.UTF8String, detail.UTF8String);
            hadError = YES;
        }

    next_file:
        i++;
    }

    return !hadError;

usage:
    dprintf(self->_errorFileHandle.fileDescriptor, command_option, *_CFGetProgname());
    return NO;
}

- (BOOL)processInitialArgs {
    NSMutableArray *args = [self->_initalArguments mutableCopy];
    NSString *commandName;

    if (args.count <= 1) {
        dprintf(self->_errorFileHandle.fileDescriptor, "No files specified.\n");
        return NO;
    }

    // Drop argv[0].
    [args removeObjectAtIndex:0];
    commandName = args[0];

    if ([commandName isEqualToString:@"-help"]) {
        self->_command = PLUCommandHelp;
        goto done;
    }

    if ([commandName isEqualToString:@"-lint"]) {
        [args removeObjectAtIndex:0];
        self->_command = PLUCommandLint;
        goto done;
    }

    if ([commandName isEqualToString:@"-convert"]) {
        [args removeObjectAtIndex:0];

        if (!args.count) {
            dprintf(self->_errorFileHandle.fileDescriptor,
                    "Missing format specifier for command.\n");
            return NO;
        }

        self->_format = args[0];
        [args removeObjectAtIndex:0];

        if (args.count >= 2 && [args[0] isEqualToString:@"-header"]) {
            NSString *format = self->_format;

            if (![format isEqual:@"objc"]) {
                dprintf(self->_errorFileHandle.fileDescriptor,
                        "-header is only valid for objc literal conversions.\n");
                return NO;
            }

            self->_command = PLUCommandConvertWithHeader;
            [args removeObjectAtIndex:0];
            goto done;
        }

        self->_command = PLUCommandConvert;
        goto done;
    }

    if ([commandName isEqualToString:@"-p"]) {
        [args removeObjectAtIndex:0];
        self->_command = PLUCommandPrint;
        goto done;
    }

    if ([commandName isEqualToString:@"-insert"] ||
        [commandName isEqualToString:@"-replace"]) {
        self->_command = [commandName isEqual:@"-replace"]
                             ? PLUCommandReplace
                             : PLUCommandInsert;

        [args removeObjectAtIndex:0];

        if (args.count <= 1) {
            dprintf(self->_errorFileHandle.fileDescriptor,
                    "'Insert' and 'Replace' require a key path, a type, and a value.\n");
            return NO;
        }

        self->_keyPath = args[0];
        [args removeObjectAtIndex:0];

        self->_type = args[0];
        [args removeObjectAtIndex:0];

        if (![self->_type isEqualToString:@"-dictionary"] &&
            ![self->_type isEqualToString:@"-array"]) {
            if (args.count < 2) {
                dprintf(self->_errorFileHandle.fileDescriptor,
                        "'Insert' and 'Replace' require a key path, a type, and a value2.\n");
                return NO;
            }

            self->_unparsedValue = args[0];
            [args removeObjectAtIndex:0];
        }

        if (self->_command == PLUCommandInsert &&
            args.count >= 2 &&
            [args[0] isEqualToString:@"-append"]) {
            self->_append = YES;
            [args removeObjectAtIndex:0];
        }

        goto done;
    }

    if ([commandName isEqualToString:@"-remove"]) {
        self->_command = PLUCommandRemove;
        [args removeObjectAtIndex:0];

        if (!args.count) {
            dprintf(self->_errorFileHandle.fileDescriptor,
                    "'Remove' requires a key path.\n");
            return NO;
        }

        self->_keyPath = args[0];
        [args removeObjectAtIndex:0];
        goto done;
    }

    if ([commandName isEqualToString:@"-extract"]) {
        [args removeObjectAtIndex:0];
        self->_command = PLUCommandExtract;

        if (args.count <= 1) {
            dprintf(self->_errorFileHandle.fileDescriptor,
                    "'Extract' requires a key path and a plist format.\n");
            return NO;
        }

        self->_keyPath = args[0];
        [args removeObjectAtIndex:0];

        self->_format = args[0];
        [args removeObjectAtIndex:0];

        if (args.count >= 2 && [args[0] isEqualToString:@"-expect"]) {
            [args removeObjectAtIndex:0];

            NSString *typeName = args[0];
            NSUInteger i;
            for (i = 1; i < 9; i++) {
                if ([PLUExpectedTypeNames[i] isEqualToString:typeName])
                    break;
            }

            if (i == 9) {
                dprintf(self->_errorFileHandle.fileDescriptor,
                        "-expect type [%s] not valid.\n",
                        [typeName UTF8String]);
                return NO;
            }

            self->_expect = i;
            [args removeObjectAtIndex:0];
        }

        goto done;
    }

    if ([commandName isEqualToString:@"-type"]) {
        [args removeObjectAtIndex:0];
        self->_command = PLUCommandType;

        if (!args.count) {
            dprintf(self->_errorFileHandle.fileDescriptor,
                    "'Extract' requires a key path.\n");
            return NO;
        }

        self->_keyPath = args[0];
        [args removeObjectAtIndex:0];

        if (args.count >= 2 && [args[0] isEqualToString:@"-expect"]) {
            [args removeObjectAtIndex:0];

            NSString *typeName = args[0];
            NSUInteger i;
            for (i = 1; i < 9; i++) {
                if ([PLUExpectedTypeNames[i] isEqualToString:typeName])
                    break;
            }

            if (i == 9) {
                dprintf(self->_errorFileHandle.fileDescriptor,
                        "-expect type [%s] not valid.\n",
                        [typeName UTF8String]);
                return NO;
            }

            self->_expect = i;
            [args removeObjectAtIndex:0];
        }

        goto done;
    }

    if ([commandName isEqualToString:@"-create"]) {
        [args removeObjectAtIndex:0];
        self->_command = PLUCommandCreate;

        if (!args.count) {
            dprintf(self->_errorFileHandle.fileDescriptor,
                    "Missing format specifier for command.\n");
            return NO;
        }

        self->_format = args[0];
        [args removeObjectAtIndex:0];
        goto done;
    }

done:
    self->_remainingOptionArgs = [args copy];
    return YES;
}

@end /* PLUContext */
