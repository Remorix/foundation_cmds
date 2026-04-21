#import <unistd.h>

#import "PLUContext.h"

int main(int __unused argc, char __unused *argv[]) {
    _exit(![[PLUContext contextWithArguments:NSProcessInfo.processInfo.arguments
                            outputFileHandle:[NSFileHandle fileHandleWithStandardOutput]
                             errorFileHandle:[NSFileHandle fileHandleWithStandardError]] execute]);
}
