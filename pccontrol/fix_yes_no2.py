import sys

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/Task.xm", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Replace TLinkShellDrainContext
old_drain_ctx = """@interface TLinkShellDrainContext : NSObject {
@private
    os_unfair_lock _lock;
}
@property (nonatomic, strong) NSMutableData *outData;
@property (nonatomic, strong) NSMutableData *errData;
@property (nonatomic, assign) NSUInteger capturedBytes;
@property (nonatomic, assign) BOOL outTruncated;
@property (nonatomic, assign) BOOL errTruncated;
- (void)appendChunk:(NSData *)chunk toStderr:(BOOL)isStderr;
@end

@implementation TLinkShellDrainContext
- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _outData = [NSMutableData data];
        _errData = [NSMutableData data];
    }
    return self;
}
- (void)appendChunk:(NSData *)chunk toStderr:(BOOL)isStderr {
    if (!chunk || chunk.length == 0) return;
    os_unfair_lock_lock(&_lock);
    NSUInteger remaining = (self.capturedBytes >= kShellMaxCapturedOutputBytes) ? 0 : (kShellMaxCapturedOutputBytes - self.capturedBytes);
    NSUInteger accepted = MIN(remaining, chunk.length);
    if (accepted > 0) {
        self.capturedBytes += accepted;
        if (isStderr) {
            [self.errData appendBytes:chunk.bytes length:accepted];
        } else {
            [self.outData appendBytes:chunk.bytes length:accepted];
        }
    }
    if (accepted < chunk.length) {
        if (isStderr) self.errTruncated = YES;
        else self.outTruncated = YES;
    }
    os_unfair_lock_unlock(&_lock);
}
@end"""

new_drain_ctx = """@interface TLinkShellDrainContext : NSObject {
@private
    os_unfair_lock _lock;
    BOOL _forceCloseReaders;
}
@property (nonatomic, strong) NSMutableData *outData;
@property (nonatomic, strong) NSMutableData *errData;
@property (nonatomic, assign) NSUInteger capturedBytes;
@property (nonatomic, assign) BOOL outTruncated;
@property (nonatomic, assign) BOOL errTruncated;
- (void)appendChunk:(NSData *)chunk toStderr:(BOOL)isStderr;
- (void)requestForceCloseReaders;
- (BOOL)shouldForceCloseReaders;
@end

@implementation TLinkShellDrainContext
- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _forceCloseReaders = false;
        _outData = [NSMutableData data];
        _errData = [NSMutableData data];
    }
    return self;
}
- (void)requestForceCloseReaders {
    os_unfair_lock_lock(&_lock);
    _forceCloseReaders = true;
    os_unfair_lock_unlock(&_lock);
}
- (BOOL)shouldForceCloseReaders {
    os_unfair_lock_lock(&_lock);
    BOOL value = _forceCloseReaders;
    os_unfair_lock_unlock(&_lock);
    return value;
}
- (void)appendChunk:(NSData *)chunk toStderr:(BOOL)isStderr {
    if (!chunk || chunk.length == 0) return;
    os_unfair_lock_lock(&_lock);
    NSUInteger remaining = (self.capturedBytes >= kShellMaxCapturedOutputBytes) ? 0 : (kShellMaxCapturedOutputBytes - self.capturedBytes);
    NSUInteger accepted = MIN(remaining, chunk.length);
    if (accepted > 0) {
        self.capturedBytes += accepted;
        if (isStderr) {
            [self.errData appendBytes:chunk.bytes length:accepted];
        } else {
            [self.outData appendBytes:chunk.bytes length:accepted];
        }
    }
    if (accepted < chunk.length) {
        if (isStderr) self.errTruncated = true;
        else self.outTruncated = true;
    }
    os_unfair_lock_unlock(&_lock);
}
@end"""

if old_drain_ctx in content:
    content = content.replace(old_drain_ctx, new_drain_ctx)

# 2. Replace the drain block section
old_drain_block = """    TLinkShellDrainContext *drainCtx = [[TLinkShellDrainContext alloc] init];
    __block BOOL forceCloseReaders = NO;

    dispatch_queue_t ioQueue = dispatch_queue_create("com.tlinkauto.shell.io", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t drainGroup = dispatch_group_create();

    void (^drainBlock)(int, BOOL) = ^(int fd, BOOL isStderr) {
        fcntl(fd, F_SETFL, O_NONBLOCK);
        while (true) {
            if (forceCloseReaders) break;
            struct pollfd pfd = { fd, POLLIN, 0 };
            int ret = poll(&pfd, 1, 100);"""

new_drain_block = """    TLinkShellDrainContext *drainCtx = [[TLinkShellDrainContext alloc] init];

    dispatch_queue_t ioQueue = dispatch_queue_create("com.tlinkauto.shell.io", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t drainGroup = dispatch_group_create();

    void (^drainBlock)(int, BOOL) = ^(int fd, BOOL isStderr) {
        fcntl(fd, F_SETFL, O_NONBLOCK);
        while (![drainCtx shouldForceCloseReaders]) {
            struct pollfd pfd = { fd, POLLIN, 0 };
            int ret = poll(&pfd, 1, 100);"""

if old_drain_block in content:
    content = content.replace(old_drain_block, new_drain_block)

# 3. Replace dispatch calls
old_dispatch = """    int outFd = outPipe[0];
    int errFd = errPipe[0];
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(outFd, NO); });
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(errFd, YES); });

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:actualTimeout];
    BOOL timedOut = NO;
    BOOL cancelled = NO;"""

new_dispatch = """    int outFd = outPipe[0];
    int errFd = errPipe[0];
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(outFd, false); });
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(errFd, true); });

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:actualTimeout];
    BOOL timedOut = false;
    BOOL cancelled = false;"""

if old_dispatch in content:
    content = content.replace(old_dispatch, new_dispatch)

# 4. Replace YES assignments
content = content.replace("timedOut = YES;", "timedOut = true;")
content = content.replace("cancelled = YES;", "cancelled = true;")
content = content.replace("forceCloseReaders = YES;", "[drainCtx requestForceCloseReaders];")
content = content.replace("result.drainForcedClosed = YES;", "result.drainForcedClosed = true;")

# 5. Fix resp assignments at the end
old_resp = """                resp[@"stdout"] = @"[Truncated due to JSON size limit]";
                resp[@"stderr"] = @"[Truncated due to JSON size limit]";
                resp[@"stdoutTruncated"] = @(YES);
                resp[@"stderrTruncated"] = @(YES);"""

new_resp = """                resp[@"stdout"] = @"[Truncated due to JSON size limit]";
                resp[@"stderr"] = @"[Truncated due to JSON size limit]";
                resp[@"stdoutTruncated"] = @(true);
                resp[@"stderrTruncated"] = @(true);"""

if old_resp in content:
    content = content.replace(old_resp, new_resp)

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/Task.xm", "w", encoding="utf-8") as f:
    f.write(content)
print("Applied all fixes")
