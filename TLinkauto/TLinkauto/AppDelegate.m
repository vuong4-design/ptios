//
//  AppDelegate.m
//  TLinkauto
//
//  Created by Jason on 2020/12/10.
//

#import "AppDelegate.h"
#import "TLinkAppDiagnostic.h"

@interface TLinkMainThreadWatchdog : NSObject
@property(nonatomic, strong) dispatch_queue_t watchdogQueue;
@property(nonatomic, assign) BOOL running;
@end

@implementation TLinkMainThreadWatchdog

+ (instancetype)sharedInstance {
    static TLinkMainThreadWatchdog *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (void)start
{
    if (self.running) {
        return;
    }

    self.running = true;

    self.watchdogQueue = dispatch_queue_create(
        "com.tlinkauto.main-watchdog",
        DISPATCH_QUEUE_SERIAL
    );

    dispatch_async(self.watchdogQueue, ^{
        while (self.running) {
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            CFAbsoluteTime sentAt = CFAbsoluteTimeGetCurrent();

            dispatch_async(dispatch_get_main_queue(), ^{
                CFAbsoluteTime delay = CFAbsoluteTimeGetCurrent() - sentAt;
                if (delay > 0.1) {
                    APP_DIAG("MAIN-STALL", "main queue delay=%.2fms", delay * 1000.0);
                }
                dispatch_semaphore_signal(semaphore);
            });

            dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
            usleep(100 * 1000);
        }
    });
}

@end

@interface AppDelegate ()
{

}

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [[TLinkMainThreadWatchdog sharedInstance] start];
    // Override point for customization after application launch.

    if (@available(iOS 13.0, *)) {
        _window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }
    
    if (@available(iOS 13.0, *)) {
        if ([_window respondsToSelector:NSSelectorFromString(@"overrideUserInterfaceStyle")]) {
            [_window setValue:@(UIUserInterfaceStyleLight) forKey:@"overrideUserInterfaceStyle"];
        }
    }
    
    return YES;
}


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}


@end
