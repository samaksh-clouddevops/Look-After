#import <Foundation/Foundation.h>

/// Firebase is configured lazily from Swift via `LookAfterFirebaseConfiguration.configureIfNeeded()`
/// (see `LookAfterApp.swift`). This file remains as a compile anchor only — `+load` was removed
/// to keep synchronous plist I/O off the pre-main critical path.

@interface LookAfterFirebaseAppBootstrap : NSObject
@end

@implementation LookAfterFirebaseAppBootstrap
@end
