#import <Foundation/Foundation.h>

// Unsupported WebKit API. Returns NO for missing selectors, exceptions or a
// rejected setting. Swift cannot catch NSException, so keep this boundary here.
FOUNDATION_EXPORT BOOL MTSetTransparentBackground(id _Nonnull view, BOOL transparent);
