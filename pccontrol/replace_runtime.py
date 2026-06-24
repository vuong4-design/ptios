import sys

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/TLinkautoJSRuntime.mm", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Update class extension
old_ext = """@interface TLinkautoJSRuntime ()
{
    TLinkautoJSCancelState *_cancelState;
    NSCondition *_sleepCondition;
    BOOL _running;
    NSString *_runId;
    NSString *_bundlePath;
    NSDictionary *_manifest;
    NSString *_consoleLogPath;
    NSString *_consoleLatestLogPath;
    NSMutableSet<NSNumber *> *_ownedFrameIds;
    NSMutableSet<NSNumber *> *_ownedImageIds;
    JSContext *_context;
    TLinkautoJSSetExecutionTimeLimitFn _setExecutionTimeLimit;
    TLinkautoJSClearExecutionTimeLimitFn _clearExecutionTimeLimit;
    BOOL _watchdogAvailable;
}"""

new_ext = """@interface TLinkautoJSRuntime ()
{
    TLinkautoJSCancelState *_cancelState;
    NSCondition *_sleepCondition;
    BOOL _running;
    NSString *_runId;
    NSString *_bundlePath;
    NSDictionary *_manifest;
    NSString *_consoleLogPath;
    NSString *_consoleLatestLogPath;
    NSMutableSet<NSNumber *> *_ownedFrameIds;
    NSMutableSet<NSNumber *> *_ownedImageIds;
    JSContext *_context;
    TLinkautoJSSetExecutionTimeLimitFn _setExecutionTimeLimit;
    TLinkautoJSClearExecutionTimeLimitFn _clearExecutionTimeLimit;
    BOOL _watchdogAvailable;
    
    dispatch_queue_t _logQueue;
    os_unfair_lock _logStateLock;
    BOOL _acceptingLogs;
    
    os_unfair_lock _handlesLock;
    BOOL _acceptingHandles;
}"""

if old_ext in content:
    content = content.replace(old_ext, new_ext)

# 2. Update init
old_init = """- (instancetype)init
{
    self = [super init];
    if (self) {
        _cancelState = new TLinkautoJSCancelState();
        _cancelState->aborted.store(false, std::memory_order_release);
        _sleepCondition = [[NSCondition alloc] init];
        _ownedFrameIds = [NSMutableSet set];
        _ownedImageIds = [NSMutableSet set];
        _setExecutionTimeLimit = (TLinkautoJSSetExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
        _clearExecutionTimeLimit = (TLinkautoJSClearExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupClearExecutionTimeLimit");
        _watchdogAvailable = TLinkautoJSWatchdogCapability(_setExecutionTimeLimit, _clearExecutionTimeLimit);
    }
    return self;
}"""

new_init = """- (instancetype)init
{
    self = [super init];
    if (self) {
        _cancelState = new TLinkautoJSCancelState();
        _cancelState->aborted.store(false, std::memory_order_release);
        _sleepCondition = [[NSCondition alloc] init];
        _ownedFrameIds = [NSMutableSet set];
        _ownedImageIds = [NSMutableSet set];
        _setExecutionTimeLimit = (TLinkautoJSSetExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
        _clearExecutionTimeLimit = (TLinkautoJSClearExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupClearExecutionTimeLimit");
        _watchdogAvailable = TLinkautoJSWatchdogCapability(_setExecutionTimeLimit, _clearExecutionTimeLimit);
        
        _logQueue = dispatch_queue_create("com.tlinkauto.js.log", DISPATCH_QUEUE_SERIAL);
        _logStateLock = OS_UNFAIR_LOCK_INIT;
        _acceptingLogs = NO;
        
        _handlesLock = OS_UNFAIR_LOCK_INIT;
        _acceptingHandles = NO;
    }
    return self;
}"""

if old_init in content:
    content = content.replace(old_init, new_init)

# 3. Update logging
old_log = """- (void)appendConsoleLogWithLevel:(NSString *)level message:(NSString *)message
{
    NSString *safeLevel = TLinkautoJSSanitizeFileComponent(level ?: @"log");
    NSString *safeMessage = [message isKindOfClass:[NSString class]] ? message : [message description];
    safeMessage = safeMessage ?: @"";
    safeMessage = [safeMessage stringByReplacingOccurrencesOfString:@"\\r" withString:@"\\\\r"];
    NSString *line = [NSString stringWithFormat:@"[%@][%@][%@] %@\\n", [[NSDate date] description], _runId ?: @"", safeLevel, safeMessage];
    [self appendLine:line toConsolePath:_consoleLogPath];
    [self appendLine:line toConsolePath:_consoleLatestLogPath];
}"""

new_log = """- (void)appendConsoleLogWithLevel:(NSString *)level message:(NSString *)message
{
    os_unfair_lock_lock(&_logStateLock);
    if (!_acceptingLogs) {
        os_unfair_lock_unlock(&_logStateLock);
        return;
    }
    os_unfair_lock_unlock(&_logStateLock);

    NSString *safeLevel = TLinkautoJSSanitizeFileComponent(level ?: @"log");
    NSString *safeMessage = [message isKindOfClass:[NSString class]] ? message : [message description];
    safeMessage = safeMessage ?: @"";
    safeMessage = [safeMessage stringByReplacingOccurrencesOfString:@"\\r" withString:@"\\\\r"];
    NSString *line = [NSString stringWithFormat:@"[%@][%@][%@] %@\\n", [[NSDate date] description], _runId ?: @"", safeLevel, safeMessage];
    
    NSString *path1 = _consoleLogPath;
    NSString *path2 = _consoleLatestLogPath;
    
    dispatch_async(_logQueue, ^{
        [self appendLine:line toConsolePath:path1];
        [self appendLine:line toConsolePath:path2];
    });
}"""

if old_log in content:
    content = content.replace(old_log, new_log)

# 4. Update handles
old_handles = """- (void)trackFrameId:(int)frameId
{
    if (frameId > 0) [_ownedFrameIds addObject:@(frameId)];
}

- (void)untrackFrameId:(int)frameId
{
    if (frameId > 0) [_ownedFrameIds removeObject:@(frameId)];
}

- (void)untrackAllFrameIds
{
    [_ownedFrameIds removeAllObjects];
}

- (void)trackImageId:(int)imageId
{
    if (imageId > 0) [_ownedImageIds addObject:@(imageId)];
}

- (void)untrackImageId:(int)imageId
{
    if (imageId > 0) [_ownedImageIds removeObject:@(imageId)];
}

- (void)releaseOwnedHandles
{
    NSArray<NSNumber *> *frameIds = [_ownedFrameIds allObjects];
    NSArray<NSNumber *> *imageIds = [_ownedImageIds allObjects];
    [_ownedFrameIds removeAllObjects];
    [_ownedImageIds removeAllObjects];

    bool wasAborted = _cancelState->aborted.load(std::memory_order_acquire);
    _cancelState->aborted.store(false, std::memory_order_release);
    for (NSNumber *frameId in frameIds) {
        [self taskResultForPayload:[NSString stringWithFormat:@"67%d", [frameId intValue]]];
    }
    for (NSNumber *imageId in imageIds) {
        [self taskResultForPayload:[NSString stringWithFormat:@"483;;%d", [imageId intValue]]];
    }
    _cancelState->aborted.store(wasAborted, std::memory_order_release);
}"""

new_handles = """- (void)trackFrameId:(int)frameId
{
    if (frameId > 0) {
        os_unfair_lock_lock(&_handlesLock);
        if (_acceptingHandles) [_ownedFrameIds addObject:@(frameId)];
        os_unfair_lock_unlock(&_handlesLock);
    }
}

- (void)untrackFrameId:(int)frameId
{
    if (frameId > 0) {
        os_unfair_lock_lock(&_handlesLock);
        [_ownedFrameIds removeObject:@(frameId)];
        os_unfair_lock_unlock(&_handlesLock);
    }
}

- (void)untrackAllFrameIds
{
    os_unfair_lock_lock(&_handlesLock);
    [_ownedFrameIds removeAllObjects];
    os_unfair_lock_unlock(&_handlesLock);
}

- (void)trackImageId:(int)imageId
{
    if (imageId > 0) {
        os_unfair_lock_lock(&_handlesLock);
        if (_acceptingHandles) [_ownedImageIds addObject:@(imageId)];
        os_unfair_lock_unlock(&_handlesLock);
    }
}

- (void)untrackImageId:(int)imageId
{
    if (imageId > 0) {
        os_unfair_lock_lock(&_handlesLock);
        [_ownedImageIds removeObject:@(imageId)];
        os_unfair_lock_unlock(&_handlesLock);
    }
}

- (void)releaseOwnedHandles
{
    os_unfair_lock_lock(&_handlesLock);
    _acceptingHandles = NO;
    NSArray<NSNumber *> *frameIds = [_ownedFrameIds allObjects];
    NSArray<NSNumber *> *imageIds = [_ownedImageIds allObjects];
    [_ownedFrameIds removeAllObjects];
    [_ownedImageIds removeAllObjects];
    os_unfair_lock_unlock(&_handlesLock);

    bool wasAborted = _cancelState->aborted.load(std::memory_order_acquire);
    _cancelState->aborted.store(false, std::memory_order_release);
    for (NSNumber *frameId in frameIds) {
        [self taskResultForPayload:[NSString stringWithFormat:@"67%d", [frameId intValue]]];
    }
    for (NSNumber *imageId in imageIds) {
        [self taskResultForPayload:[NSString stringWithFormat:@"483;;%d", [imageId intValue]]];
    }
    _cancelState->aborted.store(wasAborted, std::memory_order_release);
}"""

if old_handles in content:
    content = content.replace(old_handles, new_handles)

# 5. Update runScriptAtPath: signature and body
content = content.replace("- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest error:(NSError **)error", 
                          "- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest context:(TLinkTaskExecutionContext *)context error:(NSError **)error")

old_body_start = """    _running = YES;
    _runId = [[NSUUID UUID] UUIDString];
    _bundlePath = [bundlePath copy];
    _manifest = [manifest isKindOfClass:[NSDictionary class]] ? [manifest copy] : @{};
    [self prepareConsoleLogFiles];
    _cancelState->aborted.store(false, std::memory_order_release);"""

new_body_start = """    _running = YES;
    _runId = [[NSUUID UUID] UUIDString];
    _bundlePath = [bundlePath copy];
    _manifest = [manifest isKindOfClass:[NSDictionary class]] ? [manifest copy] : @{};
    [self prepareConsoleLogFiles];
    
    os_unfair_lock_lock(&_logStateLock);
    _acceptingLogs = YES;
    os_unfair_lock_unlock(&_logStateLock);
    
    os_unfair_lock_lock(&_handlesLock);
    _acceptingHandles = YES;
    os_unfair_lock_unlock(&_handlesLock);
    
    _cancelState->aborted.store(false, std::memory_order_release);
    
    @try {"""

if old_body_start in content:
    content = content.replace(old_body_start, new_body_start)

old_body_end = """    [self clearWatchdogForContext:context];

    BOOL success = !context.exception && ![self isAborted];
    if (!success && error) {
        NSString *message = context.exception ? [context.exception toString] : @"JavaScript execution was stopped";
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\\r\\n", message ?: @"JavaScript error"]}];
    }

    [self releaseOwnedHandles];
    _context = nil;
    _bundlePath = nil;
    _manifest = nil;
    _consoleLogPath = nil;
    _consoleLatestLogPath = nil;
    _running = NO;
    return success;"""

new_body_end = """    BOOL success = !context.exception && ![self isAborted];
    if (!success && error) {
        NSString *message = context.exception ? [context.exception toString] : @"JavaScript execution was stopped";
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\\r\\n", message ?: @"JavaScript error"]}];
    }
    return success;
    } @finally {
        [self releaseOwnedHandles];
        [self clearWatchdogForContext:_context];
        _context = nil;
        _bundlePath = nil;
        _manifest = nil;
        
        os_unfair_lock_lock(&_logStateLock);
        _acceptingLogs = NO;
        os_unfair_lock_unlock(&_logStateLock);
        dispatch_sync(_logQueue, ^{}); // flush
        
        _consoleLogPath = nil;
        _consoleLatestLogPath = nil;
        _running = NO;
    }"""

if old_body_end in content:
    content = content.replace(old_body_end, new_body_end)


with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/TLinkautoJSRuntime.mm", "w", encoding="utf-8") as f:
    f.write(content)
print("Updated runtime!")
