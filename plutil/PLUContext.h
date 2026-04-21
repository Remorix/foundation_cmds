#import <Foundation/Foundation.h>

@interface PLUContext : NSObject
@property (nonatomic, readwrite, assign) BOOL append;
@property (atomic, readwrite, strong) NSFileHandle *outputFileHandle;
@property (atomic, readwrite, strong) NSFileHandle *errorFileHandle;
@property (atomic, readwrite, strong) NSArray *initalArguments;
@property (atomic, readwrite, strong) NSArray *remainingOptionArgs;
@property (nonatomic, readwrite, assign) UInt64 command;
@property (atomic, readwrite, strong) NSString *format;
@property (nonatomic, readwrite, assign) UInt64 expect;
@property (atomic, readwrite, strong) NSString *keyPath;
@property (atomic, readwrite, strong) NSString *type;
@property (atomic, readwrite, strong) NSString *unparsedValue;

+ (PLUContext *)contextWithArguments:(NSArray *)arguments
		  outputFileHandle:(NSFileHandle *)outputFileHandle
		   errorFileHandle:(NSFileHandle *)errorFileHandle;

- (BOOL)create;
- (BOOL)convert;
- (BOOL)execute;
- (BOOL)lint;
- (BOOL)print;

- (BOOL)processInitialArgs;

@end
