#import "WebKitBackground.h"
#import <objc/message.h>
#include <string.h>

BOOL MTSetTransparentBackground(id view, BOOL transparent) {
    SEL getter = NSSelectorFromString(@"_drawsBackground");
    SEL setter = NSSelectorFromString(@"_setDrawsBackground:");
    if (![view respondsToSelector:getter] || ![view respondsToSelector:setter]) {
        return NO;
    }
    @try {
        NSMethodSignature *read = [view methodSignatureForSelector:getter];
        NSMethodSignature *write = [view methodSignatureForSelector:setter];
        if (read.numberOfArguments != 2 || write.numberOfArguments != 3 ||
            strcmp(read.methodReturnType, @encode(BOOL)) != 0 ||
            strcmp(write.methodReturnType, @encode(void)) != 0 ||
            strcmp([write getArgumentTypeAtIndex:2], @encode(BOOL)) != 0) {
            return NO;
        }
        ((void (*)(id, SEL, BOOL))objc_msgSend)(view, setter, !transparent);
        if (((BOOL (*)(id, SEL))objc_msgSend)(view, getter) == !transparent) {
            return YES;
        }
    } @catch (NSException *exception) {
        // Fall through to a best-effort restore of normal background drawing.
    }
    @try {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(view, setter, YES);
    } @catch (NSException *exception) {
        // The caller also restores opaque CSS and a public background color.
    }
    return NO;
}
