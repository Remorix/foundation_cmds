#import "PLUMutableDictionary.h"

@interface PLUMutableDictionary () {
    NSMutableDictionary *_internalDict;
}
@end

@implementation PLUMutableDictionary

+ (instancetype)dictionaryWithObjects:(const id _Nonnull __unsafe_unretained [])objects
                              forKeys:(const id<NSCopying> _Nonnull __unsafe_unretained [])keys
                                count:(NSUInteger)cnt {
    return [[PLUMutableDictionary alloc] initWithObjects:objects forKeys:keys count:cnt];
}

- (instancetype)initWithObjects:(const id _Nonnull __unsafe_unretained [])objects
                        forKeys:(const id<NSCopying> _Nonnull __unsafe_unretained [])keys
                          count:(NSUInteger)cnt {
    if (cnt) {
        for (NSUInteger i = 0; i < cnt; i++) {
            if (![(id)keys[i] isKindOfClass:[NSString class]]) {
                return nil;
            }
        }
    }

    self = [super init];
    if (!self)
        return nil;

    self->_internalDict = [[NSMutableDictionary alloc] initWithObjects:objects forKeys:keys count:cnt];
    return self;
}

- (NSUInteger)count {
    return [self->_internalDict count];
}

- (NSEnumerator *)keyEnumerator {
    return [self->_internalDict keyEnumerator];
}

- (id)objectForKey:(id)aKey {
    return [self->_internalDict objectForKey:aKey];
}

- (void)removeObjectForKey:(id)aKey {
    [self->_internalDict removeObjectForKey:aKey];
}

- (void)setObject:(id)anObject forKey:(id<NSCopying>)aKey {
    [self->_internalDict setObject:anObject forKey:aKey];
}

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath {
    NSRange r = [keyPath rangeOfString:@"."];
    if (r.location == NSNotFound) {
        [super setValue:value forKeyPath:keyPath];
        return;
    }

    NSString *firstKey = [keyPath substringToIndex:r.location];
    if ([firstKey hasPrefix:@"@"]) {
        [super setValue:value forKeyPath:keyPath];
        return;
    }

    id obj = [self valueForKey:firstKey];
    NSString *remainingKeyPath = [keyPath substringFromIndex:r.location + 1];

    if (obj) {
        [obj setValue:value forKeyPath:remainingKeyPath];
    } else if ([remainingKeyPath rangeOfString:@"."].location == NSNotFound) {
        [self setObject:value forKey:remainingKeyPath];
    }
}

@end
