#import "PLUMutableArray.h"

@interface PLUMutableArray () {
    NSMutableArray *_internalArray;
}
@end

@implementation PLUMutableArray

- (instancetype)initWithCapacity:(NSUInteger)numItems {
    self = [super init];
    if (self) {
        self->_internalArray = [[NSMutableArray alloc] initWithCapacity:numItems];
    }
    return self;
}

- (NSUInteger)count {
    return [self->_internalArray count];
}

- (void)insertObject:(id)anObject atIndex:(NSUInteger)index {
    [self->_internalArray insertObject:anObject atIndex:index];
}

- (void)removeObjectAtIndex:(NSUInteger)index {
    [self->_internalArray removeObjectAtIndex:index];
}

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
    [self->_internalArray replaceObjectAtIndex:index withObject:anObject];
}

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath {
    NSArray *parts = [keyPath componentsSeparatedByString:@"."];
    NSString *first = parts.firstObject;

    if ([first integerValue] || [first isEqualToString:@"0"]) {
        NSString *subKeyPath = (parts.count < 2) ? @"" : [keyPath substringFromIndex:first.length + 1];
        [self setValue:value forKeyPath:subKeyPath atIndex:first.integerValue];
    } else {
        [super setValue:value forKeyPath:keyPath];
    }
}

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath atIndex:(NSUInteger)index {
    id obj = nil;

    if (keyPath && keyPath.length && (obj = [self objectAtIndex:index])) {
        [obj setValue:value forKeyPath:keyPath];
    } else if (self.count == index) {
        if (value)
            [self addObject:value];
        else
            [self removeLastObject];
    } else if (value) {
        [self insertObject:value atIndex:index];
    } else {
        [self removeObjectAtIndex:index];
    }
}

- (id)objectAtIndex:(NSUInteger)index {
    return [self->_internalArray objectAtIndex:index];
}

- (id)valueForKey:(NSString *)key {
    NSInteger index = key.integerValue;

    if (index || (key.length == 1 && [key characterAtIndex:0] == '0'))
        return [self objectAtIndex:index];

    return [super valueForKey:key];
}

- (id)valueForKeyPath:(NSString *)keyPath {
    NSInteger index = keyPath.integerValue;

    if (index < 0 || (NSUInteger)index >= self->_internalArray.count)
        return nil;

    return [super valueForKeyPath:keyPath];
}

@end
