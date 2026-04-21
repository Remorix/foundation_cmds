#import <Foundation/Foundation.h>

@interface NSString (PLPropertyList)
- (id)propertyList;
@end

void usage(void) {
    puts("pl {-input <file>} {-output <file>}\n"
         "\tReads ASCII PL from stdin (or file if -input specified)\n"
         "\tand writes ASCII PL to stdout (or file if -output)\n"
         "\tNOTE: binary serialization is no longer supported");
}

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSArray *arguments = [[NSProcessInfo processInfo] arguments];
        NSString *outputFile = nil;
        NSString *inputFile = nil;
        NSData *inputData = nil;

        if ([arguments count] >= 2) {
            NSUInteger argumentCount = [arguments count];

            for (NSUInteger i = 2; i <= argumentCount; i += 2) {
                NSString *option = [arguments objectAtIndex:i - 1];

                if ([option isEqual:@"-input"] && i < argumentCount) {
                    inputFile = [arguments objectAtIndex:i];
                } else if ([option isEqual:@"-output"] && i < argumentCount) {
                    outputFile = [arguments objectAtIndex:i];
                } else {
                    usage();
                    exit(-1);
                }
            }
        }

        if (inputFile != nil) {
            inputData = [NSData dataWithContentsOfFile:inputFile];
            if (inputData == nil) {
                NSLog(@"*** Can't read file %@", inputFile);
                exit(-2);
            }

            if ([inputData length] == 0) {
                NSLog(@"*** File is zero length: %@", inputFile);
                exit(-2);
            }
        } else {
            inputData = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
            if ([inputData length] == 0) {
                exit(0);
            }
        }

        NSStringEncoding inputEncoding = NSUTF8StringEncoding;
        if ([inputData length] >= 2) {
            const unsigned char *bytes = [inputData bytes];
            if ((bytes[0] == 0xFE && bytes[1] == 0xFF) ||
                (bytes[0] == 0xFF && bytes[1] == 0xFE)) {
                inputEncoding = NSUnicodeStringEncoding;
            }
        }

        NSString *outputString = nil;
        @try {
            outputString = [[[[[NSString alloc] initWithData:inputData encoding:inputEncoding] propertyList] description]
                stringByAppendingString:@"\n"];
        } @catch (NSException *exception) {
            NSLog(@"*** Exception parsing ASCII property list: %@ %@",
                  [exception name],
                  [exception reason]);
            exit(-2);
        }

        NSData *outputData = [outputString dataUsingEncoding:NSASCIIStringEncoding];
        if (outputData == nil) {
            outputData = [outputString dataUsingEncoding:NSUnicodeStringEncoding];
        }

        if (outputFile != nil) {
            if (![outputData writeToFile:outputFile atomically:YES]) {
                NSLog(@"*** Failed writing file %@", outputFile);
                exit(-3);
            }
        } else {
            [[NSFileHandle fileHandleWithStandardOutput] writeData:outputData];
        }
    }

    return 0;
}
