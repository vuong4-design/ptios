#include "Task.h"
#include "Touch.h"
#include "Process.h"
#include "AlertBox.h"
#include "Record.h"
#include "Play.h"
#include "SocketServer.h"
#include "ScreenMatch.h"
#include "Toast.h"
#include "ColorPicker.h"
#include "Image.h"
#include "Connectivity.h"
#include "UIKeyboard.h"
#include "DeviceInfo.h"
#include "TouchIndicator/TouchIndicatorWindow.h"
#include "HardwareKey.h"
#include "Scheduler.h"
#include "RuntimeUtils.h"
#import "ScriptPlayer.h"
#import <mach/mach.h>
#include <Foundation/NSDistributedNotificationCenter.h>
#include <TextRecognization/TextRecognizer.h>
#include "UpdateCache.h"
#include "TesseractOCRTask.h"
#include "Screen.h"
#include "NSTask.h"
#include <signal.h>
#include <os/lock.h>

extern CFRunLoopRef recordRunLoop;
extern ScriptPlayer *scriptPlayer;

/*
get task type
*/
static int getTaskType(UInt8* dataArray)
{
    return (dataArray[0] - '0') * 10 + (dataArray[1] - '0');
}

static int zx_clampTouchCoord(CGFloat value)
{
    if (value < 0) value = 0;
    int fixed = (int)(value * 10.0f + 0.5f);
    if (fixed > 99999) fixed = 99999;
    return fixed;
}

static NSString *zx_touchPayload(int type, int finger, CGFloat x, CGFloat y)
{
    if (finger < 0) finger = 0;
    if (finger > 99) finger = 99;
    return [NSString stringWithFormat:@"1%d%02d%05d%05d", type, finger, zx_clampTouchCoord(x), zx_clampTouchCoord(y)];
}

static void zx_performSingleTouch(int type, int finger, CGFloat x, CGFloat y)
{
    NSString *payload = zx_touchPayload(type, finger, x, y);
    performTouchFromRawData((UInt8 *)[payload UTF8String]);
}

static NSArray<NSString *> *zx_splitTaskParts(UInt8 *eventData)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    if (!raw) return @[];
    return [raw componentsSeparatedByString:@";;"];
}

static bool zx_handleNativeTap(UInt8 *eventData, NSError **err)
{
    NSArray<NSString *> *parts = zx_splitTaskParts(eventData);
    if (parts.count < 2) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native tap format: x;;y[;;duration_ms;;finger]\r\n"}];
        return false;
    }
    CGFloat x = [parts[0] floatValue];
    CGFloat y = [parts[1] floatValue];
    int durationMs = parts.count >= 3 ? [parts[2] intValue] : 50;
    int finger = parts.count >= 4 ? [parts[3] intValue] : 0;
    if (durationMs < 0) durationMs = 0;
    zx_performSingleTouch(TOUCH_DOWN, finger, x, y);
    if (durationMs > 0) usleep((useconds_t)durationMs * 1000);
    zx_performSingleTouch(TOUCH_UP, finger, x, y);
    return true;
}

static bool zx_handleNativeSwipe(UInt8 *eventData, NSError **err)
{
    NSArray<NSString *> *parts = zx_splitTaskParts(eventData);
    if (parts.count < 5) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native swipe format: x1;;y1;;x2;;y2;;duration_ms[;;finger;;steps]\r\n"}];
        return false;
    }
    CGFloat x1 = [parts[0] floatValue];
    CGFloat y1 = [parts[1] floatValue];
    CGFloat x2 = [parts[2] floatValue];
    CGFloat y2 = [parts[3] floatValue];
    int durationMs = [parts[4] intValue];
    int finger = parts.count >= 6 ? [parts[5] intValue] : 0;
    int steps = parts.count >= 7 ? [parts[6] intValue] : durationMs / 16;
    if (durationMs < 0) durationMs = 0;
    if (steps < 2) steps = 2;
    if (steps > 120) steps = 120;

    zx_performSingleTouch(TOUCH_DOWN, finger, x1, y1);
    int sleepPerStep = steps > 0 ? durationMs * 1000 / steps : 0;
    for (int i = 1; i < steps; i++) {
        if (sleepPerStep > 0) usleep((useconds_t)sleepPerStep);
        CGFloat t = (CGFloat)i / (CGFloat)steps;
        zx_performSingleTouch(TOUCH_MOVE, finger, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
    }
    if (sleepPerStep > 0) usleep((useconds_t)sleepPerStep);
    zx_performSingleTouch(TOUCH_UP, finger, x2, y2);
    return true;
}

static bool zx_parseGesturePoint(NSString *text, CGFloat *x, CGFloat *y)
{
    NSArray<NSString *> *xy = [text componentsSeparatedByString:@","];
    if (xy.count != 2) return false;
    if (x) *x = [xy[0] floatValue];
    if (y) *y = [xy[1] floatValue];
    return true;
}

static bool zx_handleNativeGesture(UInt8 *eventData, NSError **err)
{
    NSArray<NSString *> *parts = zx_splitTaskParts(eventData);
    if (parts.count < 3) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native gesture format: finger;;duration_ms;;x,y|x,y|...\r\n"}];
        return false;
    }
    int finger = [parts[0] intValue];
    int durationMs = [parts[1] intValue];
    NSArray<NSString *> *pointTexts = [parts[2] componentsSeparatedByString:@"|"];
    if (pointTexts.count < 2) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native gesture requires at least two points.\r\n"}];
        return false;
    }
    if (durationMs < 0) durationMs = 0;

    CGFloat x = 0, y = 0;
    if (!zx_parseGesturePoint(pointTexts[0], &x, &y)) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid first gesture point.\r\n"}];
        return false;
    }
    zx_performSingleTouch(TOUCH_DOWN, finger, x, y);

    int intervals = (int)pointTexts.count - 1;
    int sleepPerInterval = intervals > 0 ? durationMs * 1000 / intervals : 0;
    for (NSUInteger i = 1; i < pointTexts.count; i++) {
        if (!zx_parseGesturePoint(pointTexts[i], &x, &y)) {
            zx_performSingleTouch(TOUCH_UP, finger, x, y);
            if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid gesture point.\r\n"}];
            return false;
        }
        zx_performSingleTouch(TOUCH_MOVE, finger, x, y);
        if (sleepPerInterval > 0) usleep((useconds_t)sleepPerInterval);
    }
    zx_performSingleTouch(TOUCH_UP, finger, x, y);
    return true;
}

static bool zx_handleNativeBatch(UInt8 *eventData, NSError **err)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    if (!raw || raw.length == 0) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native batch format: command||command, command starts with 10/62/63/64.\r\n"}];
        return false;
    }

    NSArray<NSString *> *commands = [raw componentsSeparatedByString:@"||"];
    for (NSString *cmd in commands) {
        if (cmd.length < 2) continue;
        int task = [[cmd substringToIndex:2] intValue];
        NSString *payload = [cmd substringFromIndex:2];
        UInt8 *payloadBytes = (UInt8 *)[payload UTF8String];
        if (task == TASK_PERFORM_TOUCH) {
            performTouchFromRawData(payloadBytes);
        } else if (task == TASK_NATIVE_TAP) {
            if (!zx_handleNativeTap(payloadBytes, err)) return false;
        } else if (task == TASK_NATIVE_SWIPE) {
            if (!zx_handleNativeSwipe(payloadBytes, err)) return false;
        } else if (task == TASK_NATIVE_GESTURE) {
            if (!zx_handleNativeGesture(payloadBytes, err)) return false;
        } else {
            if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Unsupported batch task: %d\r\n", task]}];
            return false;
        }
    }
    return true;
}

// === runShell drain/timeout support (Group A) ===
//
// Technical note (A7): the cancellation path below sends SIGTERM/SIGKILL to the
// DIRECT child only (the /usr/bin/sudo process launched by NSTask). If the shell
// spawns its own descendants, those are NOT guaranteed to be reaped or to close
// the pipe. Reliable hard-cancellation of a whole process tree requires launching
// in a dedicated process group (e.g. posix_spawn + setpgid, then killpg). That is
// deferred to a later phase and tracked in the plan.

static const NSUInteger kShellMaxCapturedOutputBytes = 1024 * 1024; // 1 MiB total (stdout+stderr)
static const NSUInteger kShellReadChunkBytes = 16 * 1024;          // 16 KiB
static const double kShellDefaultTimeout = 30.0;
static const double kShellMinTimeout = 1.0;
static const double kShellMaxTimeout = 300.0;
static const double kShellTerminateGrace = 1.5;

// Shared capture budget for both readers. capturedBytes/flags are guarded by lock.
typedef struct {
    os_unfair_lock lock;
    NSUInteger capturedBytes;
} ZXShellBudget;

// Drain one file handle to EOF. CRITICAL (A2): once the shared budget is exhausted
// we KEEP reading and discard, so the pipe never fills and the child never blocks.
// Stopping early would reintroduce the original deadlock.
static void ZXDrainShellHandle(NSFileHandle *handle, NSMutableData *outBuffer, ZXShellBudget *budget, BOOL *outTruncated)
{
    if (!handle) return;
    while (true) {
        @autoreleasepool {
            NSData *chunk = nil;
            @try {
                chunk = [handle readDataOfLength:kShellReadChunkBytes];
            } @catch (NSException *e) {
                // Handle closed underneath us (timeout cleanup). Stop draining.
                break;
            }
            if (chunk.length == 0) {
                break; // EOF
            }
            os_unfair_lock_lock(&budget->lock);
            NSUInteger remaining = (budget->capturedBytes >= kShellMaxCapturedOutputBytes)
                ? 0
                : (kShellMaxCapturedOutputBytes - budget->capturedBytes);
            NSUInteger accepted = MIN(remaining, (NSUInteger)chunk.length);
            if (accepted > 0) {
                budget->capturedBytes += accepted;
            }
            os_unfair_lock_unlock(&budget->lock);

            if (accepted > 0) {
                [outBuffer appendBytes:chunk.bytes length:accepted];
            }
            if (accepted < (NSUInteger)chunk.length && outTruncated) {
                *outTruncated = YES;
            }
            // else: budget full -> keep looping, read+discard until EOF.
        }
    }
}

/**
Process Task
*/
void processTask(UInt8 *buff, CFWriteStreamRef writeStreamRef)
{
    //NSLog(@"### com.tlinkauto.springboard: task type: %d. Data: %s", getTaskType(buff), buff);
    UInt8 *eventData = buff + 0x2;
    int taskType = getTaskType(buff);

    //for touching
    if (taskType == TASK_PERFORM_TOUCH)
    {
        @autoreleasepool{
            performTouchFromRawData(eventData);
        }
    }
    else if (taskType == TASK_PERFORM_TOUCH_ACK)
    {
        @autoreleasepool{
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            char *sep = strstr((char *)eventData, ";;");
            if (!sep) {
                notifyClient((UInt8*)"1;;touch_ack_bad_payload\r\n", writeStreamRef);
                return;
            }

            *sep = '\0';
            char *seq = (char *)eventData;
            UInt8 *touchData = (UInt8 *)(sep + 2);
            performTouchFromRawData(touchData);
            int dispatchUs = (int)((CFAbsoluteTimeGetCurrent() - start) * 1000000.0);
            NSString *response = [NSString stringWithFormat:@"0;;%s;;%d\r\n", seq, dispatchUs];
            notifyClient((UInt8*)[response UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_TAP)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeTap(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_SWIPE)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeSwipe(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_GESTURE)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeGesture(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_BATCH)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeBatch(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_PROCESS_BRING_FOREGROUND) //bring to foreground
    {
        @autoreleasepool{   
            switchProcessForegroundFromRawData(eventData);
            notifyClient((UInt8*)"0\r\n", writeStreamRef); 
        }
    }
    else if (taskType == TASK_SHOW_ALERT_BOX)
    {
        @autoreleasepool{   
            NSError *err = nil;
            showAlertBoxFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_USLEEP)
    {
        if (writeStreamRef)
        {
            int usleepTime = 0;
            @try{
                usleepTime = atoi((char*)eventData);
            }
            @catch (NSException *exception) {
                NSLog(@"com.tlinkauto.springboard: Debug: %@", exception.reason);
                return;
            }
            //NSLog(@"com.tlinkauto.springboard: sleep %d microseconds", usleepTime);
            usleep(usleepTime);
            notifyClient((UInt8*)"0;;Sleep ends\r\n", writeStreamRef); 
        }
        else
        {
            int usleepTime = 0;

            @try{
                usleepTime = atoi((char*)eventData);
            }
            @catch (NSException *exception) {
                NSLog(@"com.tlinkauto.springboard: Debug: %@", exception.reason);
                return;
            }
            //NSLog(@"com.tlinkauto.springboard: sleep %d microseconds", usleepTime);
            usleep(usleepTime);
        }

    }
    else if (taskType == TASK_RUN_SHELL)
    {
        @autoreleasepool{
            // Payload format: command  OR  timeoutSeconds;;command
            // (the bridge may prefix an optional timeout; if absent, default applies)
            NSString *rawPayload = [NSString stringWithUTF8String:(const char *)eventData] ?: @"";
            double timeout = kShellDefaultTimeout;
            NSString *command = rawPayload;
            NSRange sepRange = [rawPayload rangeOfString:@";;"];
            if (sepRange.location != NSNotFound) {
                NSString *maybeTimeout = [rawPayload substringToIndex:sepRange.location];
                NSScanner *scanner = [NSScanner scannerWithString:maybeTimeout];
                double parsed = 0;
                if ([scanner scanDouble:&parsed] && [scanner isAtEnd] && parsed > 0) {
                    timeout = parsed;
                    command = [rawPayload substringFromIndex:sepRange.location + 2];
                }
            }
            // Clamp timeout to a safe range. 0/infinite is intentionally disallowed.
            if (timeout < kShellMinTimeout) timeout = kShellMinTimeout;
            if (timeout > kShellMaxTimeout) timeout = kShellMaxTimeout;

            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:@"/usr/bin/sudo"];
            [task setArguments:@[@"/usr/bin/tlinkautob", @"-e", command]];

            // Separate pipes so each stream can be drained independently.
            NSPipe *outPipe = [NSPipe pipe];
            NSPipe *errPipe = [NSPipe pipe];
            [task setStandardOutput:outPipe];
            [task setStandardError:errPipe];
            NSFileHandle *outHandle = [outPipe fileHandleForReading];
            NSFileHandle *errHandle = [errPipe fileHandleForReading];

            NSMutableData *outData = [NSMutableData data];
            NSMutableData *errData = [NSMutableData data];
            __block BOOL outTruncated = NO;
            __block BOOL errTruncated = NO;
            ZXShellBudget budget;
            budget.lock = OS_UNFAIR_LOCK_INIT;
            budget.capturedBytes = 0;
            ZXShellBudget *budgetPtr = &budget;

            dispatch_queue_t ioQueue = dispatch_queue_create("com.tlinkauto.shell.io", DISPATCH_QUEUE_CONCURRENT);
            dispatch_group_t drainGroup = dispatch_group_create();

            // A1: start readers BEFORE launch so the pipe is always being drained.
            // Capture budgetPtr (a pointer) rather than the struct: blocks capture
            // automatic variables as const-by-value, which would make &budget a
            // const pointer. budget lives on the stack until dispatch_group_wait below.
            dispatch_group_async(drainGroup, ioQueue, ^{
                ZXDrainShellHandle(outHandle, outData, budgetPtr, &outTruncated);
            });
            dispatch_group_async(drainGroup, ioQueue, ^{
                ZXDrainShellHandle(errHandle, errData, budgetPtr, &errTruncated);
            });

            BOOL launched = NO;
            @try {
                [task launch];
                launched = YES;
            } @catch (NSException *e) {
                NSLog(@"com.tlinkauto.springboard: runShell launch failed: %@", e.reason);
            }

            BOOL timedOut = NO;
            if (launched) {
                // A4: bounded wait instead of waitUntilExit. Poll termination with a deadline.
                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
                while ([task isRunning]) {
                    if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
                        timedOut = YES;
                        break;
                    }
                    usleep(20 * 1000); // 20 ms poll
                }

                if (timedOut) {
                    // A5: SIGTERM -> grace -> SIGKILL.
                    pid_t pid = [task processIdentifier];
                    if (pid > 0) kill(pid, SIGTERM);
                    NSDate *graceDeadline = [NSDate dateWithTimeIntervalSinceNow:kShellTerminateGrace];
                    while ([task isRunning] && [[NSDate date] compare:graceDeadline] == NSOrderedAscending) {
                        usleep(20 * 1000);
                    }
                    if ([task isRunning] && pid > 0) {
                        kill(pid, SIGKILL);
                    }
                }
            }

            // Close write ends / handles so readers hit EOF, then wait for drain with a bounded deadline.
            @try { [outHandle closeFile]; } @catch (NSException *e) {}
            @try { [errHandle closeFile]; } @catch (NSException *e) {}
            dispatch_group_wait(drainGroup, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));

            int status = (launched && !timedOut) ? [task terminationStatus] : -1;

            NSString *outStr = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"";
            NSString *errStr = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"";
            NSString *combined = errStr.length > 0 ? [outStr stringByAppendingString:errStr] : outStr;
            NSString *safeOutput = [[combined stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
            BOOL truncated = outTruncated || errTruncated;
            if (truncated) {
                safeOutput = [safeOutput stringByAppendingFormat:@"\\n[output truncated: exceeded %lu bytes]", (unsigned long)kShellMaxCapturedOutputBytes];
            }

            if (timedOut) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command timed out after %.0fs: %@\r\n", timeout, safeOutput] UTF8String], writeStreamRef);
            } else if (!launched) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command failed to launch\r\n"] UTF8String], writeStreamRef);
            } else if (status == 0) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", safeOutput] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command failed (%d): %@\r\n", status, safeOutput] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TOUCH_RECORDING_START)
    {
        @autoreleasepool {
            NSError *err = nil;
            startRecording(writeStreamRef, &err);    
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TOUCH_RECORDING_STOP)
    {
        @autoreleasepool {
            stopRecording(); 
            notifyClient((UInt8*)"0\r\n", writeStreamRef); 
        }
    }
    else if (taskType == TASK_PLAY_SCRIPT)
    {
        @autoreleasepool {
            NSError *err = nil;
            playScript((UInt8*)eventData, &err);
            if (err)
            {
                setLastScriptError([err localizedDescription]);
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_PLAY_SCRIPT_FORCE_STOP)
    {
        @autoreleasepool {
            NSError *err = nil;
            stopScriptPlaying(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEMPLATE_MATCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            CGRect result = screenMatchFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%.2f;;%.2f;;%.2f;;%.2f\r\n", 
                result.origin.x, result.origin.y, result.size.width, result.size.height] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_SHOW_TOAST)
    {
        @autoreleasepool {
            NSError *err = nil;
            showToastFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_COLOR_PICKER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSDictionary *rgb = getRGBFromRawData(eventData, &err); 
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%d;;%d;;%d\r\n", [rgb[@"red"] intValue], [rgb[@"green"] intValue], [rgb[@"blue"] intValue]] UTF8String], writeStreamRef);
            }
            rgb = nil;
        }
    }
    else if (taskType == TASK_TEXT_INPUT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *result = inputTextFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", result] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_GET_DEVICE_INFO)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *deviceInfo = getDeviceInfoFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", deviceInfo] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TOUCH_INDICATOR)
    {
        @autoreleasepool {
            NSError *err = nil;
            handleTouchIndicatorTaskWithRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEXT_RECOGNIZER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *text = performTextRecognizerTextFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", text] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_COLOR_SEARCHER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *returndata = searchRGBFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", returndata] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_HARDWARE_KEY)
    {
        @autoreleasepool {
            NSError *err = nil;
            sendHardwareKeyEventFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_KILL)
    {
        @autoreleasepool {
            NSError *err = nil;
            killAppFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_STATE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = appStateFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_INFO)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *info = appInfoFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", info] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRONTMOST_APP_ID)
    {
        @autoreleasepool {
            NSString *frontApp = frontMostAppId();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", frontApp] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_FRONTMOST_APP_ORIENTATION)
    {
        @autoreleasepool {
            NSString *orientation = frontMostAppOrientation();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", orientation] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SET_AUTO_LAUNCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            setAutoLaunchFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_LIST_AUTO_LAUNCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *list = listAutoLaunch(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", list ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_SET_TIMER)
    {
        @autoreleasepool {
            NSError *err = nil;
            setTimerFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_REMOVE_TIMER)
    {
        @autoreleasepool {
            NSError *err = nil;
            removeTimerFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_KEEP_AWAKE)
    {
        @autoreleasepool {
            NSError *err = nil;
            keepAwakeFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_PID)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *pid = appPidFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", pid ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRONTMOST_PID)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *pid = frontMostPidFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", pid ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_PATHS)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *paths = appPathsFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", paths ?: @";;"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_LIST_BUNDLES)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *result = listBundlesFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", result ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_OPEN_URL)
    {
        @autoreleasepool {
            NSError *err = nil;
            (void)openUrlFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_WIFI)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = wifiTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_BLUETOOTH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = bluetoothTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_AIRPLANE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = airplaneTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_CELLULAR_DATA)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = cellularDataTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_VPN)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = vpnTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_HELLO_STATUS)
    {
        @autoreleasepool {
            UIDevice *dev = [UIDevice currentDevice];
            NSString *name = dev.name ?: @"";
            NSString *systemName = dev.systemName ?: @"iOS";
            NSString *systemVersion = dev.systemVersion ?: @"";
            NSString *model = dev.model ?: @"";

            BOOL playing = false;
            NSString *bundlePath = @"";
            if (scriptPlayer) {
                playing = [scriptPlayer isPlaying];
                bundlePath = [scriptPlayer getCurrentBundlePath] ?: @"";
            }

            NSDictionary *payload = @{
                @"tlinkauto": @{
                    @"protocols": @[@"v0", @"v1"],
                    @"port": @6000,
                },
                @"device": @{
                    @"name": name,
                    @"system_name": systemName,
                    @"system_version": systemVersion,
                    @"model": model,
                },
                @"script": @{
                    @"is_playing": @(playing),
                    @"bundle_path": bundlePath,
                    @"last_error": getLastScriptError() ?: @"",
                    @"last_error_ts": @(getLastScriptErrorTs()),
                },
            };

            NSError *jsonErr = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonErr];
            if (!jsonData || jsonErr) {
                notifyClient((UInt8*)"1;;Failed to encode hello status.\r\n", writeStreamRef);
                return;
            }
            NSString *b64 = [jsonData base64EncodedStringWithOptions:0];
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", b64 ?: @""] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SCREEN_KEEP)
    {
        @autoreleasepool {
            NSError *err = nil;
            handleScreenKeepTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_IMAGE_OBJECT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleImageObjectTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else if (ret && [ret length] > 0)
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRAME_CAPTURE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFrameCaptureTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRAME_RELEASE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFrameReleaseTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FIND_IMAGE_IN_FRAME)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFindImageInFrameTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @"-1;;-1;;0;;0;;-1;;-1;;0;;0;;0;;0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_COLOR_IN_FRAME)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleColorInFrameTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRAME_BATCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFrameBatchTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_OCR_TESSERACT_REGION)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleTesseractOCRTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FIND_IMAGE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFindImageTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @"-1;;-1;;0;;0;;-1;;-1;;0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_STOP_SCRIPT)
    {
        @autoreleasepool {
            NSError *err = nil;
            stopScriptFromRawData(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_DIALOG)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *response = dialogFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", response ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_CLEAR_DIALOG)
    {
        @autoreleasepool {
            NSError *err = nil;
            clearDialogValues(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_ROOT_DIR)
    {
        @autoreleasepool {
            NSString *path = rootDirValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_CURRENT_DIR)
    {
        @autoreleasepool {
            NSString *path = currentDirValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_BOT_PATH)
    {
        @autoreleasepool {
            NSString *path = botPathValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SCREENSHOT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *resultPath = handleScreenshotTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else if (resultPath)
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", resultPath] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_UPDATE_CACHE)
    {
        @autoreleasepool{
            NSError *err = nil;
            updateCacheFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[@"0\r\n" UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEST)
    {

    }
}
