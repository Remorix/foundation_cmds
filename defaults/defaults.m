#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSString ()
- (id)propertyList;
@end

@interface NSDate ()
+ (NSDate *)dateWithString:(NSString *)string;
+ (NSDate *)dateWithNaturalLanguageString:(NSString *)string;
@end

extern void _CFPrefSetInvalidPropertyListDeletionEnabled(Boolean enabled);
extern CFDictionaryRef _CFPreferencesCopyApplicationMap(CFStringRef user, CFStringRef host);
extern void _CFPreferencesFlushCachesForIdentifier(CFStringRef domain, CFStringRef user);
extern void _CFPrefsSetSynchronizeIsSynchronous(Boolean synchronous);
extern void _CFPrefsSynchronizeForProcessTermination(void);
extern CFStringRef _CFXPreferencesGetByHostIdentifierString(void);

#if TARGET_OS_OSX
#define DEFAULTS_INLINE_NORETURN static inline __attribute__((always_inline, noreturn))
#define DEFAULTS_SPLIT_HELPER static inline __attribute__((always_inline))
#else
#define DEFAULTS_INLINE_NORETURN __attribute__((noreturn))
#define DEFAULTS_SPLIT_HELPER
#endif

static const char DefaultsUsageText[] =
    "Command line interface to a user's defaults.\n"
    "Syntax:\n"
    "\n"
    "'defaults' [-currentHost | -host <hostname>] followed by one of the following:\n"
    "\n"
    "  read                                 shows all defaults\n"
    "  read <domain>                        shows defaults for given domain\n"
    "  read <domain> <key>                  shows defaults for given domain, key\n"
    "\n"
    "  read-type <domain> <key>             shows the type for the given domain, key\n"
    "\n"
    "  write <domain> <domain_rep>          writes domain (overwrites existing)\n"
    "  write <domain> <key> <value>         writes key for domain\n"
    "\n"
    "  rename <domain> <old_key> <new_key>  renames old_key to new_key\n"
    "\n"
    "  delete <domain>                      deletes domain\n"
    "  delete <domain> <key>                deletes key in domain\n"
    "\n"
    "  import <domain> <path to plist>      writes the plist at path to domain\n"
    "  import <domain> -                    writes a plist from stdin to domain\n"
    "  export <domain> <path to plist>      saves domain as a binary plist to path\n"
    "  export <domain> -                    writes domain as an xml plist to stdout\n"
    "  domains                              lists all domains\n"
    "  find <word>                          lists all entries containing word\n"
    "  help                                 print this help\n"
    "\n"
    "<domain> is ( <domain_name> | -app <application_name> | -globalDomain )\n"
    "         or a path to a file omitting the '.plist' extension\n"
    "\n"
    "<value> is one of:\n"
    "  <value_rep>\n"
    "  -string <string_value>\n"
    "  -data <hex_digits>\n"
    "  -int[eger] <integer_value>\n"
    "  -float  <floating-point_value>\n"
    "  -bool[ean] (true | false | yes | no)\n"
    "  -date <date_rep>\n"
    "  -array <value1> <value2> ...\n"
    "  -array-add <value1> <value2> ...\n"
    "  -dict <key1> <value1> <key2> <value2> ...\n"
    "  -dict-add <key1> <value1> ...\n";

DEFAULTS_INLINE_NORETURN void DefaultsPrintUsageAndExit(void);
void DefaultsPrint(NSString *format, ...);
CFStringRef DefaultsCopyDomainFromArguments(NSArray *arguments, NSUInteger *cursor);
CFStringRef DefaultsCopyHostFromArguments(NSArray *arguments, NSUInteger *cursor);
CFStringRef DefaultsCopyUserForDomain(CFStringRef *domainSlot);
DEFAULTS_INLINE_NORETURN void DefaultsHandleFind(CFStringRef host, NSArray *arguments, NSUInteger cursor);
DEFAULTS_INLINE_NORETURN void DefaultsPrintHelpAndExit(void);
DEFAULTS_INLINE_NORETURN void DefaultsHandleDomains(CFStringRef host);
DEFAULTS_INLINE_NORETURN void DefaultsHandleReadAll(CFStringRef host);
DEFAULTS_INLINE_NORETURN void DefaultsHandleRead(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor);
void DefaultsHandleReadType(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) __attribute__((noreturn));
void DefaultsHandleWrite(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) __attribute__((noreturn));
void DefaultsHandleRename(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) __attribute__((noreturn));
void DefaultsHandleDelete(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) __attribute__((noreturn));
BOOL DefaultsHandleImport(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor);
void DefaultsHandleExport(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) __attribute__((noreturn));
BOOL DefaultsObjectContainsString(id object, NSString *needle);
NSArray *DefaultsCopyDomainSearchList(CFTypeRef domain, CFStringRef user, CFStringRef host, BOOL filterByExistingPath);
id DefaultsParsePropertyListValue(NSString *value);
BOOL DefaultsSynchronizeDomain(CFStringRef domain, CFStringRef user, CFStringRef host);
id DefaultsParseValueArguments(NSArray *arguments, NSUInteger *cursor, BOOL allowCompositeTypes, BOOL *didUseAddOperation);

void DefaultsPrint(NSString *format, ...) {
    va_list arguments;
    NSString *string;
    NSData *data;

    va_start(arguments, format);
    string = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    data = [string dataUsingEncoding:NSNonLossyASCIIStringEncoding allowLossyConversion:YES];
    if (data != nil) {
        fprintf(stdout, "%.*s", (int)data.length, (const char *)data.bytes);
    }
}

CFStringRef DefaultsCopyDomainFromArguments(NSArray *arguments, NSUInteger *cursor) {
    NSUInteger index;
    NSString *domain;
    NSFileManager *fileManager;
    BOOL isDirectory;
    NSUInteger applicationIndex;
    NSString *applicationName;
    NSString *applicationPath;
    NSArray *applicationDirectories;
    NSUInteger directoryCount;
    NSUInteger directoryIndex;
    CFURLRef bundleURL;
    CFBundleRef bundle;
    CFStringRef bundleIdentifier;
    CFURLRef executableURL;

    index = *cursor;
    if (index >= arguments.count) {
        DefaultsPrintUsageAndExit();
    }

    domain = [arguments objectAtIndex:index];
    if (domain == nil) {
        DefaultsPrintUsageAndExit();
    }

    if ([domain isEqual:@"-globalDomain"] ||
        [domain isEqual:@"-g"] ||
        [domain isEqual:@"Apple Global Domain"] ||
        [domain isEqual:@"NSGlobalDomain"]) {
        *cursor += 1;
        return kCFPreferencesAnyApplication;
    }

    if (![domain isEqual:@"-app"]) {
        *cursor += 1;
        return (__bridge CFStringRef)domain;
    }

    fileManager = [NSFileManager defaultManager];
    isDirectory = NO;
    applicationIndex = *cursor + 1;
    if (applicationIndex == arguments.count) {
        DefaultsPrintUsageAndExit();
    }

    index = *cursor;
    *cursor += 2;
    applicationName = [arguments objectAtIndex:index + 1];
    applicationPath = applicationName;
    if (![fileManager fileExistsAtPath:applicationName isDirectory:&isDirectory] || !isDirectory) {
        applicationDirectories = NSSearchPathForDirectoriesInDomains(NSAllApplicationsDirectory, NSAllDomainsMask, YES);
        if (applicationDirectories.count < 1) {
            applicationPath = nil;
        } else {
            applicationPath = nil;
            directoryCount = applicationDirectories.count;
            for (directoryIndex = 0; directoryIndex != directoryCount; directoryIndex += 1) {
                applicationPath = [[[applicationDirectories objectAtIndex:directoryIndex] stringByAppendingPathComponent:applicationName] stringByAppendingPathExtension:@"app"];
                if ([fileManager fileExistsAtPath:applicationPath isDirectory:&isDirectory] && isDirectory) {
                    break;
                }
            }
            if (directoryIndex == directoryCount) {
                applicationPath = nil;
            }
        }
    }

    if (applicationPath == nil) {
        NSLog(@"Couldn't find an application named \"%@\"; defaults unchanged", applicationName);
        exit(1);
    }

    bundleURL = CFURLCreateWithFileSystemPath(NULL, (__bridge CFStringRef)applicationPath, kCFURLPOSIXPathStyle, true);
    if (bundleURL == NULL) {
        NSLog(@"Couldn't open application %@; defaults unchanged", applicationPath);
        exit(1);
    }

    bundle = CFBundleCreate(NULL, bundleURL);
    CFRelease(bundleURL);
    if (bundle == NULL) {
        NSLog(@"Couldn't open application %@; defaults unchanged", applicationPath);
        exit(1);
    }

    bundleIdentifier = CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleIdentifierKey);
    domain = (__bridge NSString *)bundleIdentifier;
    if (bundleIdentifier == NULL || CFStringGetLength(bundleIdentifier) == 0) {
        executableURL = CFBundleCopyExecutableURL(bundle);
        if (executableURL != NULL) {
            domain = CFBridgingRelease(CFURLCopyLastPathComponent(executableURL));
            CFRelease(executableURL);
        }
    }

    CFRelease(bundle);
    if (domain == nil) {
        NSLog(@"Can't determine domain name for application %@; defaults unchanged", applicationPath);
        exit(1);
    }

    return (__bridge CFStringRef)domain;
}

DEFAULTS_INLINE_NORETURN
void DefaultsPrintUsageAndExit(void) {
    DefaultsPrint(@"%s", DefaultsUsageText);
    exit(-1);
}

CFStringRef DefaultsCopyHostFromArguments(NSArray *arguments, NSUInteger *cursor) {
    NSUInteger index;
    NSString *token;

    index = *cursor;
    if (index >= arguments.count) {
        return kCFPreferencesAnyHost;
    }

    token = [arguments objectAtIndex:index];
    if (token == nil) {
        return kCFPreferencesAnyHost;
    }

    if ([token isEqual:@"-currentHost"]) {
        *cursor += 1;
        return kCFPreferencesCurrentHost;
    }

    if (![token isEqual:@"-host"]) {
        return kCFPreferencesAnyHost;
    }

    if (*cursor + 1 == arguments.count) {
        DefaultsPrintUsageAndExit();
    }

    index = *cursor;
    *cursor += 2;
    return (__bridge CFStringRef)[arguments objectAtIndex:index + 1];
}

CFStringRef DefaultsCopyUserForDomain(CFStringRef *domainSlot) {
    NSString *domain;

    domain = (__bridge NSString *)*domainSlot;
    if ([domain rangeOfString:@"/Library/Preferences/"].location) {
        if (![domain rangeOfString:[@"~/Library/Preferences/" stringByExpandingTildeInPath]].location) {
            /* Why?? */
            [domain length];
        }
        return kCFPreferencesCurrentUser;
    }

    return [domain length] ? kCFPreferencesAnyUser : kCFPreferencesCurrentUser;
}

DEFAULTS_SPLIT_HELPER __attribute__((noreturn))
void DefaultsHandleFind(CFStringRef host, NSArray *arguments, NSUInteger cursor) {
    id applications;
    NSString *searchString;
    NSUInteger foundCount;

    if (cursor == arguments.count) {
        DefaultsPrintUsageAndExit();
    }

    searchString = [arguments objectAtIndex:cursor];
    foundCount = 0;
#if TARGET_OS_OSX
    applications = CFBridgingRelease(_CFPreferencesCopyApplicationMap(kCFPreferencesCurrentUser, host));
#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    applications = CFBridgingRelease(CFPreferencesCopyApplicationList(kCFPreferencesCurrentUser, host));
#pragma clang diagnostic pop
#endif

    for (NSString *domainName in applications) {
        BOOL isGlobalDomain;
        CFStringRef searchDomain;
        CFDictionaryRef values;
        NSArray *keys;
        NSMutableDictionary *matchingEntries;

        isGlobalDomain = [domainName isEqualToString:(__bridge id)kCFPreferencesAnyApplication];
#if TARGET_OS_OSX
        if (isGlobalDomain) {
            searchDomain = kCFPreferencesAnyApplication;
        } else {
            searchDomain = (__bridge CFStringRef)[[[[(NSDictionary *)applications objectForKey:domainName] objectAtIndex:0] URLByAppendingPathComponent:domainName] path];
        }
#else
        searchDomain = (__bridge CFStringRef)domainName;
#endif
        values = CFPreferencesCopyMultiple(NULL, searchDomain, kCFPreferencesCurrentUser, host);
        keys = [((__bridge NSDictionary *)values).allKeys sortedArrayUsingSelector:@selector(compare:)];
        matchingEntries = nil;
        for (NSString *key in keys) {
            id value;

            value = [(__bridge NSDictionary *)values objectForKey:key];
            if (DefaultsObjectContainsString(domainName, searchString) || DefaultsObjectContainsString(key, searchString) || DefaultsObjectContainsString(value, searchString)) {
                if (matchingEntries == nil) {
                    matchingEntries = [NSMutableDictionary dictionary];
                }
                [matchingEntries setObject:value forKey:key];
            }
        }

        if (matchingEntries != nil) {
            NSString *displayDomain;

            displayDomain = isGlobalDomain ? @"Apple Global Domain" : domainName;
#if TARGET_OS_OSX
            DefaultsPrint(@"Found %lu keys in domain '%@': %@\n",
                          (unsigned long)matchingEntries.count,
                          displayDomain,
                          matchingEntries.description);
#else
            DefaultsPrint(@"Found %ld keys in domain '%@': %@\n",
                          (long)matchingEntries.count,
                          displayDomain,
                          matchingEntries.description);
#endif
            foundCount += 1;
        }
        if (values != NULL) {
            CFRelease(values);
        }
    }

    if (foundCount == 0) {
        NSLog(@"No domain, key, nor value containing '%@'", searchString);
    }
    exit(0);
}

DEFAULTS_INLINE_NORETURN
void DefaultsPrintHelpAndExit(void) {
    DefaultsPrint(@"%s", DefaultsUsageText);
    exit(0);
}

DEFAULTS_SPLIT_HELPER __attribute__((noreturn))
void DefaultsHandleDomains(CFStringRef host) {
    NSArray *domains;
    NSUInteger globalDomainIndex;

#if TARGET_OS_OSX
    {
        NSDictionary *applicationMap;

        applicationMap = CFBridgingRelease(_CFPreferencesCopyApplicationMap(kCFPreferencesCurrentUser, host));
        domains = applicationMap.allKeys;
    }
#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    domains = CFBridgingRelease(CFPreferencesCopyApplicationList(kCFPreferencesCurrentUser, host));
#pragma clang diagnostic pop
#endif

    globalDomainIndex = [domains indexOfObject:(__bridge id)kCFPreferencesAnyApplication];
    if (globalDomainIndex != NSNotFound) {
        NSMutableArray *mutableDomains;

        mutableDomains = [domains mutableCopy];
        [mutableDomains removeObjectAtIndex:globalDomainIndex];
        domains = mutableDomains;
    }

    DefaultsPrint(@"%@\n", [[domains sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]);
    exit(0);
}

DEFAULTS_SPLIT_HELPER __attribute__((noreturn))
void DefaultsHandleReadAll(CFStringRef host) {
    id applications;
    NSMutableDictionary *result;

    result = [NSMutableDictionary new];
#if TARGET_OS_OSX
    applications = CFBridgingRelease(_CFPreferencesCopyApplicationMap(kCFPreferencesCurrentUser, host));
#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    applications = CFBridgingRelease(CFPreferencesCopyApplicationList(kCFPreferencesCurrentUser, host));
#pragma clang diagnostic pop
#endif

    for (NSString *domainName in applications) {
        CFStringRef searchDomain;
        CFDictionaryRef values;
        NSString *displayDomain;

#if TARGET_OS_OSX
        searchDomain = (__bridge CFStringRef)[[[[(NSDictionary *)applications objectForKey:domainName] objectAtIndex:0] URLByAppendingPathComponent:domainName] path];
#else
        searchDomain = (__bridge CFStringRef)domainName;
#endif
        values = CFPreferencesCopyMultiple(NULL, searchDomain, kCFPreferencesCurrentUser, host);
        if (values != NULL) {
            displayDomain = [domainName isEqual:(__bridge id)kCFPreferencesAnyApplication] ? @"Apple Global Domain" : domainName;
            [result setObject:(__bridge id)values forKey:displayDomain];
            CFRelease(values);
        }
    }

    DefaultsPrint(@"%@\n", result.description);
    exit(0);
}

DEFAULTS_SPLIT_HELPER __attribute__((noreturn))
void DefaultsHandleRead(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) {
    CFStringRef resolvedDomain;
    CFPropertyListRef value;

#if TARGET_OS_OSX
    resolvedDomain = (__bridge CFStringRef)[DefaultsCopyDomainSearchList(domain, user, host, YES) objectAtIndex:0];
#else
    domain = (__bridge CFTypeRef)((__bridge NSString *)domain);
    if ([(__bridge NSString *)domain hasPrefix:@"/"]) {
        domain = (__bridge CFTypeRef)[(__bridge NSString *)domain stringByResolvingSymlinksInPath];
    }
    resolvedDomain = (__bridge CFStringRef)[[NSArray arrayWithObject:(__bridge id)domain] objectAtIndex:0];
#endif

    if (arguments.count == cursor) {
        value = CFPreferencesCopyMultiple(NULL, resolvedDomain, user, host);
        if (value == NULL || !((__bridge NSDictionary *)value).count) {
            NSString *displayDomain;

            displayDomain = [(__bridge NSString *)resolvedDomain isEqual:(__bridge id)kCFPreferencesAnyApplication] ? @"Apple Global Domain" : (__bridge NSString *)resolvedDomain;
            NSLog(@"\nDomain %@ does not exist\n", displayDomain);
            exit(1);
        }
    } else {
        NSString *key;

        key = [arguments objectAtIndex:cursor];
        value = CFPreferencesCopyValue((__bridge CFStringRef)key, resolvedDomain, user, host);
        if (value == NULL) {
            NSLog(@"\nThe domain/default pair of (%@, %@) does not exist\n", resolvedDomain, key);
            exit(1);
        }
    }

    DefaultsPrint(@"%@\n", [(__bridge id)value description]);
    exit(0);
}

void DefaultsHandleReadType(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) {
    CFStringRef resolvedDomain;
    NSString *key;
    CFPropertyListRef value;
    CFTypeID valueType;

#if TARGET_OS_OSX
    resolvedDomain = (__bridge CFStringRef)[DefaultsCopyDomainSearchList(domain, user, host, YES) objectAtIndex:0];
#else
    domain = (__bridge CFTypeRef)((__bridge NSString *)domain);
    if ([(__bridge NSString *)domain hasPrefix:@"/"]) {
        domain = (__bridge CFTypeRef)[(__bridge NSString *)domain stringByResolvingSymlinksInPath];
    }
    resolvedDomain = (__bridge CFStringRef)[[NSArray arrayWithObject:(__bridge id)domain] objectAtIndex:0];
#endif
    if (arguments.count == cursor) {
        DefaultsPrintUsageAndExit();
    }

    key = [arguments objectAtIndex:cursor];
    value = CFPreferencesCopyValue((__bridge CFStringRef)key, resolvedDomain, user, host);
    if (value == NULL) {
        NSLog(@"\nThe domain/default pair of (%@, %@) does not exist\n", resolvedDomain, key);
        exit(1);
    }

    DefaultsPrint(@"Type is ");
    valueType = CFGetTypeID(value);
    if (valueType == CFStringGetTypeID()) {
        DefaultsPrint(@"string\n");
    } else if (valueType == CFDataGetTypeID()) {
        DefaultsPrint(@"data\n");
    } else if (valueType == CFNumberGetTypeID()) {
        if (CFNumberIsFloatType((CFNumberRef)value)) {
            DefaultsPrint(@"float\n");
        } else {
            DefaultsPrint(@"integer\n");
        }
    } else if (valueType == CFBooleanGetTypeID()) {
        DefaultsPrint(@"boolean\n");
    } else if (valueType == CFDateGetTypeID()) {
        DefaultsPrint(@"date\n");
    } else if (valueType == CFArrayGetTypeID()) {
        DefaultsPrint(@"array\n");
    } else if (valueType == CFDictionaryGetTypeID()) {
        DefaultsPrint(@"dictionary\n");
    } else {
        NSLog(@"Found a value that is not of a known property list type");
        exit(1);
    }

    exit(0);
}

void DefaultsHandleWrite(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) {
    NSUInteger valueCursor;
    CFStringRef resolvedDomain;
    NSUInteger argumentCount;
    NSString *key;
    id propertyList;
    BOOL didUseAddOperation;
    id existingValue;
    CFStringRef writeDomain;

#if TARGET_OS_OSX
    resolvedDomain = (__bridge CFStringRef)[DefaultsCopyDomainSearchList(domain, user, host, YES) objectAtIndex:0];
#else
    domain = (__bridge CFTypeRef)((__bridge NSString *)domain);
    if ([(__bridge NSString *)domain hasPrefix:@"/"]) {
        domain = (__bridge CFTypeRef)[(__bridge NSString *)domain stringByResolvingSymlinksInPath];
    }
    resolvedDomain = (__bridge CFStringRef)[[NSArray arrayWithObject:(__bridge id)domain] objectAtIndex:0];
#endif
    argumentCount = arguments.count;
    if (argumentCount == cursor) {
        DefaultsPrintUsageAndExit();
    }

    key = [arguments objectAtIndex:cursor];
    if (cursor + 1 == argumentCount) {
        NSArray *allKeys;
        NSMutableArray *keysToRemove;
        NSArray *existingKeys;

        propertyList = DefaultsParsePropertyListValue(key);
        if ([propertyList isKindOfClass:[NSDictionary class]]) {
            allKeys = ((NSDictionary *)propertyList).allKeys;
            existingKeys = CFBridgingRelease(CFPreferencesCopyKeyList(resolvedDomain, user, host));
            if (existingKeys != nil) {
                keysToRemove = existingKeys.mutableCopy;
                [keysToRemove removeObjectsInArray:allKeys];
            } else {
                keysToRemove = nil;
            }
            CFPreferencesSetMultiple((__bridge CFDictionaryRef)propertyList, (__bridge CFArrayRef)keysToRemove, resolvedDomain, user, host);
            DefaultsSynchronizeDomain(resolvedDomain, user, host);
            exit(0);
        }

        NSLog(@"\nRep argument is not a dictionary\nDefaults have not been changed.\n");
        exit(1);
    }

    didUseAddOperation = NO;
    valueCursor = cursor + 1;
    propertyList = DefaultsParseValueArguments(arguments, &valueCursor, YES, &didUseAddOperation);
    if (valueCursor < argumentCount) {
        NSLog(@"Unexpected argument %@; leaving defaults unchanged.", [arguments objectAtIndex:valueCursor]);
        exit(1);
    }

    if (didUseAddOperation) {
        existingValue = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key, resolvedDomain, user, host));
        if ([propertyList isKindOfClass:[NSArray class]]) {
            if (existingValue != nil) {
                if (![existingValue isKindOfClass:[NSArray class]]) {
                    NSLog(@"Value for key %@ is not an array; cannot append.  Leaving defaults unchanged.", key);
                    exit(1);
                }
                propertyList = [existingValue arrayByAddingObjectsFromArray:propertyList];
            }
        } else if (existingValue != nil) {
            NSMutableDictionary *dictionaryValue;

            if (![existingValue isKindOfClass:[NSDictionary class]]) {
                NSLog(@"Value for key %@ is not a dictionary; cannot append.  Leaving defaults unchanged.", key);
                exit(1);
            }
            dictionaryValue = [existingValue mutableCopy];
            [dictionaryValue addEntriesFromDictionary:propertyList];
            propertyList = dictionaryValue;
        }
    }

    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)propertyList, resolvedDomain, user, host);
    if (DefaultsSynchronizeDomain(resolvedDomain, user, host)) {
        exit(0);
    }

    writeDomain = resolvedDomain;
    if ([(__bridge NSString *)resolvedDomain isEqual:(__bridge id)kCFPreferencesAnyApplication]) {
        writeDomain = CFSTR("Apple Global Domain");
    }
    NSLog(@"Could not write domain %@; exiting", writeDomain);
    exit(1);
}

void DefaultsHandleRename(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) {
    CFStringRef resolvedDomain;
    NSString *oldKey;
    NSString *newKey;
    CFPropertyListRef value;
    CFStringRef writeDomain;

#if TARGET_OS_OSX
    resolvedDomain = (__bridge CFStringRef)[DefaultsCopyDomainSearchList(domain, user, host, YES) objectAtIndex:0];
#else
    domain = (__bridge CFTypeRef)((__bridge NSString *)domain);
    if ([(__bridge NSString *)domain hasPrefix:@"/"]) {
        domain = (__bridge CFTypeRef)[(__bridge NSString *)domain stringByResolvingSymlinksInPath];
    }
    resolvedDomain = (__bridge CFStringRef)[[NSArray arrayWithObject:(__bridge id)domain] objectAtIndex:0];
#endif
    if (arguments.count != cursor + 2) {
        DefaultsPrintUsageAndExit();
    }

    oldKey = [arguments objectAtIndex:cursor];
    newKey = [arguments objectAtIndex:cursor + 1];
    value = CFPreferencesCopyValue((__bridge CFStringRef)oldKey, resolvedDomain, user, host);
    if (value != NULL) {
        CFPreferencesSetValue((__bridge CFStringRef)newKey, value, resolvedDomain, user, host);
        CFPreferencesSetValue((__bridge CFStringRef)oldKey, NULL, resolvedDomain, user, host);
        if (DefaultsSynchronizeDomain(resolvedDomain, user, host)) {
            exit(0);
        }

        writeDomain = resolvedDomain;
        if ([(__bridge NSString *)resolvedDomain isEqual:(__bridge id)kCFPreferencesAnyApplication]) {
            writeDomain = CFSTR("Apple Global Domain");
        }
        NSLog(@"Failed to write domain %@", writeDomain);
    } else {
        writeDomain = resolvedDomain;
        if ([(__bridge NSString *)resolvedDomain isEqual:(__bridge id)kCFPreferencesAnyApplication]) {
            writeDomain = CFSTR("Apple Global Domain");
        }
        NSLog(@"Key %@ does not exist in domain %@; leaving defaults unchanged", oldKey, writeDomain);
    }

    exit(1);
}

void DefaultsHandleDelete(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) {
    NSArray *searchList;
    BOOL changed;
    NSString *key;
#if !TARGET_OS_OSX
    CFTypeRef searchDomain;
#endif

    if (arguments.count == cursor) {
#if TARGET_OS_OSX
        searchList = DefaultsCopyDomainSearchList(domain, user, host, NO);
#else
        searchDomain = domain;
        if ([(__bridge NSString *)searchDomain hasPrefix:@"/"]) {
            searchDomain = (__bridge CFTypeRef)[(__bridge NSString *)searchDomain stringByResolvingSymlinksInPath];
        }
        searchList = [NSArray arrayWithObject:(__bridge id)searchDomain];
#endif
        changed = NO;
        for (NSString *resolvedDomain in searchList) {
            CFArrayRef keys;

            keys = CFPreferencesCopyKeyList((__bridge CFStringRef)resolvedDomain, user, host);
            if (keys != NULL) {
                CFPreferencesSetMultiple(NULL, keys, (__bridge CFStringRef)resolvedDomain, user, host);
                if (DefaultsSynchronizeDomain((__bridge CFStringRef)resolvedDomain, user, host)) {
                    changed = YES;
                }
            }
        }
        if (changed) {
            exit(0);
        }
    } else {
        if (arguments.count != cursor + 1) {
            DefaultsPrintUsageAndExit();
        }

        key = [arguments objectAtIndex:cursor];
#if TARGET_OS_OSX
        searchList = DefaultsCopyDomainSearchList(domain, user, host, NO);
#else
        searchDomain = domain;
        if ([(__bridge NSString *)searchDomain hasPrefix:@"/"]) {
            searchDomain = (__bridge CFTypeRef)[(__bridge NSString *)searchDomain stringByResolvingSymlinksInPath];
        }
        searchList = [NSArray arrayWithObject:(__bridge id)searchDomain];
#endif
        changed = NO;
        for (NSString *resolvedDomain in searchList) {
            CFPropertyListRef value;

            value = CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)resolvedDomain, user, host);
            if (value != NULL) {
                CFRelease(value);
                CFPreferencesSetValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)resolvedDomain, user, host);
                if (DefaultsSynchronizeDomain((__bridge CFStringRef)resolvedDomain, user, host)) {
                    changed = YES;
                }
            }
        }
        if (changed) {
            exit(0);
        }
    }

    NSLog(@"\nDomain (%@) not found.\nDefaults have not been changed.\n", (__bridge id)domain);
    exit(1);
}

BOOL DefaultsHandleImport(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) {
    NSString *path;
    NSData *data;
    NSError *error;
    id propertyList;
    CFStringRef resolvedDomain;

    if (arguments.count == cursor) {
        NSLog(@"\nNeed a path to read from");
        exit(1);
    }

    path = [arguments objectAtIndex:cursor];
    if ([[path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@"-"]) {
        data = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
    } else {
        data = [NSData dataWithContentsOfFile:path];
    }

    if (data == nil) {
        NSLog(@"Could not read data from %@", path);
        exit(1);
    }

    error = nil;
    propertyList = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error];
    if (propertyList == nil) {
        NSLog(@"Could not parse property list from %@ due to %@", path, error);
        exit(1);
    }

    if (![propertyList isKindOfClass:[NSDictionary class]]) {
        NSLog(@"Property list %@ was not a dictionary\nDefaults have not been changed.\n", propertyList);
        exit(1);
    }

#if TARGET_OS_OSX
    resolvedDomain = (__bridge CFStringRef)[DefaultsCopyDomainSearchList(domain, user, host, YES) objectAtIndex:0];
#else
    domain = (__bridge CFTypeRef)((__bridge NSString *)domain);
    if ([(__bridge NSString *)domain hasPrefix:@"/"]) {
        domain = (__bridge CFTypeRef)[(__bridge NSString *)domain stringByResolvingSymlinksInPath];
    }
    resolvedDomain = (__bridge CFStringRef)[[NSArray arrayWithObject:(__bridge id)domain] objectAtIndex:0];
#endif
    CFPreferencesSetMultiple((__bridge CFDictionaryRef)propertyList, NULL, resolvedDomain, user, host);
    return DefaultsSynchronizeDomain(resolvedDomain, user, host);
}

void DefaultsHandleExport(CFStringRef host, CFTypeRef domain, CFStringRef user, NSArray *arguments, NSUInteger cursor) {
    CFStringRef resolvedDomain;
    NSString *path;
    CFDictionaryRef values;
    NSError *error;
    NSData *data;

#if TARGET_OS_OSX
    resolvedDomain = (__bridge CFStringRef)[DefaultsCopyDomainSearchList(domain, user, host, YES) objectAtIndex:0];
#else
    domain = (__bridge CFTypeRef)((__bridge NSString *)domain);
    if ([(__bridge NSString *)domain hasPrefix:@"/"]) {
        domain = (__bridge CFTypeRef)[(__bridge NSString *)domain stringByResolvingSymlinksInPath];
    }
    resolvedDomain = (__bridge CFStringRef)[[NSArray arrayWithObject:(__bridge id)domain] objectAtIndex:0];
#endif
    if (arguments.count == cursor) {
        NSLog(@"\nNeed a path to write to");
        exit(1);
    }

    path = [arguments objectAtIndex:cursor];
    if ([[path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@"-"]) {
        path = nil;
    }

    values = CFPreferencesCopyMultiple(NULL, resolvedDomain, user, host);
    if (values != NULL) {
        error = nil;
        data = [NSPropertyListSerialization dataWithPropertyList:(__bridge id)values
                                                          format:(path != nil ? NSPropertyListBinaryFormat_v1_0 : NSPropertyListXMLFormat_v1_0)
                                                         options:0
                                                           error:&error];
        if (data != nil) {
            if (path != nil) {
                [data writeToFile:path atomically:YES];
            } else {
                [[NSFileHandle fileHandleWithStandardOutput] writeData:data];
            }
            exit(0);
        }

        NSLog(@"Could not export domain %@ to %@ due to %@", resolvedDomain, path, error);
    } else {
        NSLog(@"\nThe domain %@ does not exist\n", resolvedDomain);
    }

    exit(1);
}

BOOL DefaultsObjectContainsString(id object, NSString *needle) {
    if ([object isKindOfClass:[NSString class]]) {
        return [object rangeOfString:needle options:NSCaseInsensitiveSearch].length != 0;
    }

    if ([object isKindOfClass:[NSArray class]]) {
        NSInteger index;

        for (index = (NSInteger)((NSArray *)object).count - 1; index != -1; index -= 1) {
            if (DefaultsObjectContainsString([object objectAtIndex:(NSUInteger)index], needle)) {
                return YES;
            }
        }
        return NO;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSEnumerator *keyEnumerator;
        id key;

        keyEnumerator = [object keyEnumerator];
        do {
            key = keyEnumerator.nextObject;
        } while (key != nil && !DefaultsObjectContainsString(key, needle) && !DefaultsObjectContainsString([object objectForKey:key], needle));
        return key != nil;
    }

    return NO;
}

NSArray *DefaultsCopyDomainSearchList(CFTypeRef domain, CFStringRef user, CFStringRef host, BOOL filterByExistingPath) {
    NSDictionary *applicationMap;
    id domainEntries;
    NSMutableArray *searchList;

    if (CFEqual(kCFPreferencesAnyApplication, domain)) {
        return [NSArray arrayWithObject:(__bridge id)domain];
    }

    applicationMap = CFBridgingRelease(_CFPreferencesCopyApplicationMap(user, host));
    searchList = [NSMutableArray array];
    if (applicationMap != nil) {
        domainEntries = [applicationMap objectForKey:(__bridge id)domain];
        if (domainEntries != nil) {
            if (filterByExistingPath) {
                for (id entry in domainEntries) {
                    NSString *path;

                    path = ((NSURL *)entry).path;
                    if ([path rangeOfString:(__bridge NSString *)domain].location != NSNotFound) {
                        [searchList addObject:[path stringByAppendingPathComponent:(__bridge NSString *)domain]];
                    }
                }
                if (!searchList.count) {
                    [searchList addObject:(__bridge id)domain];
                }
            } else {
                for (id entry in domainEntries) {
                    [searchList addObject:[((NSURL *)entry).path stringByAppendingPathComponent:(__bridge NSString *)domain]];
                }
            }
            return searchList;
        }
    }

    [searchList addObject:(__bridge id)domain];
    return searchList;
}

id DefaultsParsePropertyListValue(NSString *value) {
    id propertyList;

    if ([value rangeOfString:@"\""].location == NSNotFound &&
        [value rangeOfString:@"("].location == NSNotFound &&
        [value rangeOfString:@")"].location == NSNotFound &&
        [value rangeOfString:@"]"].location == NSNotFound &&
        [value rangeOfString:@"["].location == NSNotFound &&
        [value rangeOfString:@"{"].location == NSNotFound &&
        [value rangeOfString:@"}"].location == NSNotFound &&
        [value rangeOfString:@">"].location == NSNotFound &&
        [value rangeOfString:@"<"].location == NSNotFound) {
        value = [NSString stringWithFormat:@"\"%@\"", value];
    }

    propertyList = [value propertyList];
    if (propertyList == nil) {
        NSLog(@"Could not parse: %@.  Try single-quoting it.", value);
        exit(1);
    }

    return propertyList;
}

BOOL DefaultsSynchronizeDomain(CFStringRef domain, CFStringRef user, CFStringRef host) {
    BOOL synchronized;

    synchronized = CFPreferencesSynchronize(domain, user, host) != 0;
    _CFPrefsSynchronizeForProcessTermination();
    _CFPreferencesFlushCachesForIdentifier(domain, user);
    return synchronized;
}

id DefaultsParseValueArguments(NSArray *arguments, NSUInteger *cursor, BOOL allowCompositeTypes, BOOL *didUseAddOperation) {
    NSUInteger argumentCount;
    NSString *token;

    argumentCount = arguments.count;
    if (didUseAddOperation != NULL) {
        *didUseAddOperation = NO;
    }
    if (*cursor == argumentCount) {
        DefaultsPrintUsageAndExit();
    }

    token = [arguments objectAtIndex:*cursor];
    *cursor += 1;
    if ([token isEqual:@"-string"]) {
        if (*cursor != argumentCount) {
            *cursor += 1;
            return [arguments objectAtIndex:*cursor - 1];
        }
        DefaultsPrintUsageAndExit();
    }

    if ([token isEqual:@"-data"]) {
        NSString *hexString;
        NSUInteger length;
        CFMutableDataRef mutableData;
        UInt8 byte;
        NSUInteger index;

        byte = 0;
        if (*cursor == argumentCount) {
            DefaultsPrintUsageAndExit();
        }

        hexString = [arguments objectAtIndex:*cursor];
        length = hexString.length;
        *cursor += 1;
        mutableData = CFDataCreateMutable(NULL, 0);
        if (length != 0) {
            if ((length & 1) != 0) {
                unsigned int characterCode;
                char offset;

                characterCode = [hexString characterAtIndex:0];
                if (characterCode - '0' < 10U) {
                    offset = -'0';
                } else if (characterCode - 'a' < 6U) {
                    offset = -'a' + 10;
                } else if (characterCode - 'A' < 6U) {
                    offset = -'A' + 10;
                } else {
                    DefaultsPrintUsageAndExit();
                }
                byte = (UInt8)(offset + characterCode);
                index = 1;
                CFDataAppendBytes(mutableData, &byte, 1);
            } else {
                index = 0;
            }

            while (index < length) {
                unsigned int highCharacterCode;
                unsigned int lowCharacterCode;
                char highOffset;
                char lowOffset;

                highCharacterCode = [hexString characterAtIndex:index];
                if (highCharacterCode - '0' < 10U) {
                    highOffset = -'0';
                } else if (highCharacterCode - 'a' < 6U) {
                    highOffset = -'a' + 10;
                } else if (highCharacterCode - 'A' < 6U) {
                    highOffset = -'A' + 10;
                } else {
                    DefaultsPrintUsageAndExit();
                }

                byte = (UInt8)(16 * (highOffset + highCharacterCode));
                lowCharacterCode = [hexString characterAtIndex:index + 1];
                if (lowCharacterCode - '0' < 10U) {
                    lowOffset = -'0';
                } else if (lowCharacterCode - 'a' < 6U) {
                    lowOffset = -'a' + 10;
                } else if (lowCharacterCode - 'A' < 6U) {
                    lowOffset = -'A' + 10;
                } else {
                    DefaultsPrintUsageAndExit();
                }

                byte = (UInt8)(byte + lowOffset + lowCharacterCode);
                CFDataAppendBytes(mutableData, &byte, 1);
                index += 2;
            }
        }

        return CFBridgingRelease(mutableData);
    }

    if ([token isEqual:@"-int"] || [token isEqual:@"-integer"]) {
        if (*cursor == argumentCount) {
            DefaultsPrintUsageAndExit();
        }

        *cursor += 1;
        return [NSNumber numberWithLongLong:[[arguments objectAtIndex:*cursor - 1] longLongValue]];
    }

    if ([token isEqual:@"-float"]) {
        if (*cursor != argumentCount) {
            *cursor += 1;
            return [NSNumber numberWithFloat:[[arguments objectAtIndex:*cursor - 1] floatValue]];
        }
        DefaultsPrintUsageAndExit();
    }

    if ([token isEqual:@"-bool"] || [token isEqual:@"-boolean"]) {
        NSString *booleanString;

        if (*cursor == argumentCount) {
            DefaultsPrintUsageAndExit();
        }

        booleanString = [arguments objectAtIndex:*cursor];
        *cursor += 1;
        if ([booleanString caseInsensitiveCompare:@"yes"] == NSOrderedSame || [booleanString caseInsensitiveCompare:@"true"] == NSOrderedSame) {
            return (__bridge id)kCFBooleanTrue;
        }
        if ([booleanString caseInsensitiveCompare:@"no"] == NSOrderedSame || [booleanString caseInsensitiveCompare:@"false"] == NSOrderedSame) {
            return (__bridge id)kCFBooleanFalse;
        }
        DefaultsPrintUsageAndExit();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if ([token isEqual:@"-date"]) {
        NSString *dateString;
        NSDate *dateValue;

        if (*cursor != argumentCount) {
            dateString = [arguments objectAtIndex:*cursor];
            *cursor += 1;

            dateValue = [NSDate dateWithString:dateString];
            if (dateValue != nil) {
                return dateValue;
            }

            dateValue = [NSDate dateWithNaturalLanguageString:dateString];
            if (dateValue != nil) {
                return dateValue;
            }
        }
        DefaultsPrintUsageAndExit();
    }
#pragma clang diagnostic pop

    if ([token isEqual:@"-array"] || [token isEqual:@"-array-add"]) {
        NSMutableArray *arrayValue;

        if (!allowCompositeTypes) {
            NSLog(@"Cannot nest composite types (arrays and dictionaries); exiting");
            exit(1);
        }
        if (didUseAddOperation != NULL) {
            *didUseAddOperation = [token isEqual:@"-array-add"];
        }
        arrayValue = [NSMutableArray new];
        while (*cursor < argumentCount) {
            [arrayValue addObject:DefaultsParseValueArguments(arguments, cursor, NO, NULL)];
        }
        return arrayValue;
    }

    if ([token isEqual:@"-dict"] || [token isEqual:@"-dict-add"]) {
        NSMutableDictionary *dictionaryValue;

        if (!allowCompositeTypes) {
            NSLog(@"Cannot nest composite types (arrays and dictionaries); exiting");
            exit(1);
        }
        if (didUseAddOperation != NULL) {
            *didUseAddOperation = [token isEqual:@"-dict-add"];
        }

        dictionaryValue = [NSMutableDictionary new];
        if (*cursor >= argumentCount) {
            return dictionaryValue;
        }

        while (1) {
            id key;

            key = DefaultsParseValueArguments(arguments, cursor, NO, NULL);
            if (![key isKindOfClass:[NSString class]]) {
                NSLog(@"Dictionary keys must be strings");
                exit(1);
            }
            if (*cursor >= argumentCount) {
                NSLog(@"Key %@ lacks a corresponding value", key);
                exit(1);
            }
            [dictionaryValue setObject:DefaultsParseValueArguments(arguments, cursor, NO, NULL) forKey:key];
            if (*cursor >= argumentCount) {
                return dictionaryValue;
            }
        }
    }

    return DefaultsParsePropertyListValue(token);
}

int main(void) {
    @autoreleasepool {
        NSArray *arguments;
        NSString *command;
        CFStringRef domain;
        CFStringRef host;
        CFStringRef user;
        CFStringRef effectiveHost;
        NSUInteger argumentCount;
        NSUInteger cursor;

        arguments = NSProcessInfo.processInfo.arguments;
        argumentCount = arguments.count;
        cursor = 1;
        if (argumentCount <= 1) {
            DefaultsPrintUsageAndExit();
        }

        if (argumentCount == 2 && [[arguments objectAtIndex:1] isEqual:@"printHostIdentifier"]) {
            puts([(__bridge NSString *)_CFXPreferencesGetByHostIdentifierString() UTF8String]);
            return 0;
        }

        host = DefaultsCopyHostFromArguments(arguments, &cursor);
        if (cursor == argumentCount || host == NULL) {
            DefaultsPrintUsageAndExit();
        }

        _CFPrefsSetSynchronizeIsSynchronous(true);
        _CFPrefSetInvalidPropertyListDeletionEnabled(false);

        command = [[arguments objectAtIndex:cursor] uppercaseString];
        cursor += 1;

        if ([command isEqual:@"FIND"]) {
            DefaultsHandleFind(host, arguments, cursor);
        }
        if ([command isEqual:@"HELP"]) {
            DefaultsPrintHelpAndExit();
        }
        if ([command isEqual:@"DOMAINS"]) {
            DefaultsHandleDomains(host);
        }
        if ([command isEqual:@"READ"] && cursor == argumentCount) {
            DefaultsHandleReadAll(host);
        }

        domain = DefaultsCopyDomainFromArguments(arguments, &cursor);
        if (domain == NULL) {
            DefaultsPrintUsageAndExit();
        }

        user = DefaultsCopyUserForDomain(&domain);
        effectiveHost = (host == kCFPreferencesAnyHost && user == kCFPreferencesAnyUser) ? kCFPreferencesCurrentHost : host;

        if ([command isEqual:@"READ"]) {
            DefaultsHandleRead(effectiveHost, domain, user, arguments, cursor);
        }
        if ([command isEqual:@"READ-TYPE"]) {
            DefaultsHandleReadType(effectiveHost, domain, user, arguments, cursor);
        }
        if ([command isEqual:@"WRITE"]) {
            DefaultsHandleWrite(effectiveHost, domain, user, arguments, cursor);
        }
        if ([command isEqual:@"RENAME"]) {
            DefaultsHandleRename(effectiveHost, domain, user, arguments, cursor);
        }
        if ([command isEqual:@"DELETE"] || [command isEqual:@"REMOVE"]) {
            DefaultsHandleDelete(effectiveHost, domain, user, arguments, cursor);
        }
        if ([command isEqual:@"IMPORT"]) {
            DefaultsHandleImport(effectiveHost, domain, user, arguments, cursor);
            return 0;
        }
        if ([command isEqual:@"EXPORT"]) {
            DefaultsHandleExport(effectiveHost, domain, user, arguments, cursor);
        }

        DefaultsPrintUsageAndExit();
    }
}
