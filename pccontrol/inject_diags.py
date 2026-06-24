import sys
import re

# 1. UPDATE ScriptPlayer.xm
with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/ScriptPlayer.xm", "r", encoding="utf-8") as f:
    sp = f.read()

if '#import "TLinkDiagnostic.h"' not in sp:
    sp = sp.replace('#import "ScriptPlayer.h"', '#import "ScriptPlayer.h"\n#import "TLinkDiagnostic.h"')

# runScript: changes
old_js_branch = """    } else if ([runtime isEqualToString:@"javascriptcore"] || [fileExtension isEqualToString:@"js"]) {
        if (!tlinkautoJavaScriptRuntimeEnabled()) {"""

new_js_branch = """    } else if ([runtime isEqualToString:@"javascriptcore"] || [fileExtension isEqualToString:@"js"]) {
        CFAbsoluteTime requestAt = CFAbsoluteTimeGetCurrent();
        JS_DIAG("P0", "play requested");
        
        if (!tlinkautoJavaScriptRuntimeEnabled()) {"""

if old_js_branch in sp:
    sp = sp.replace(old_js_branch, new_js_branch)

old_dispatch_js = """        dispatch_async(_jsSerialQueue, ^{
            [self executeJSIteration:session filePath:entryFilePath foregroundApp:foregroundApp];
        });"""

new_dispatch_js = """        dispatch_async(_jsSerialQueue, ^{
            [self executeJSIteration:session filePath:entryFilePath foregroundApp:foregroundApp requestAt:requestAt];
        });"""

if old_dispatch_js in sp:
    sp = sp.replace(old_dispatch_js, new_dispatch_js)


# executeJSIteration changes
old_exec_js = """- (void)executeJSIteration:(TLinkScriptSession *)session filePath:(NSString *)filePath foregroundApp:(NSString *)foregroundApp {
    os_unfair_lock_lock(&_playerLock);
    if (_currentSession != session || [session.cancellationToken isCancelled]) {
        os_unfair_lock_unlock(&_playerLock);
        return;
    }
    TLinkautoJSRuntime *runtime = [[TLinkautoJSRuntime alloc] init];
    _currentRuntime = runtime;
    _state = TLinkScriptStateRunning;
    os_unfair_lock_unlock(&_playerLock);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->switchAppBeforePlaying) bringAppForeground(foregroundApp);
    });

    NSError *runError = nil;
    BOOL ok = [runtime runScriptAtPath:filePath bundlePath:scriptBundlePath manifest:currentManifest context:session.taskContext error:&runError];"""

new_exec_js = """- (void)executeJSIteration:(TLinkScriptSession *)session filePath:(NSString *)filePath foregroundApp:(NSString *)foregroundApp requestAt:(CFAbsoluteTime)requestAt {
    JS_DIAG("P2", "entered js queue, wait=%.2fms", (CFAbsoluteTimeGetCurrent() - requestAt) * 1000.0);
    
    os_unfair_lock_lock(&_playerLock);
    if (_currentSession != session || [session.cancellationToken isCancelled]) {
        os_unfair_lock_unlock(&_playerLock);
        return;
    }
    TLinkautoJSRuntime *runtime = [[TLinkautoJSRuntime alloc] init];
    JS_DIAG("P4", "runtime allocated, total=%.2fms", (CFAbsoluteTimeGetCurrent() - requestAt) * 1000.0);
    _currentRuntime = runtime;
    _state = TLinkScriptStateRunning;
    os_unfair_lock_unlock(&_playerLock);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->switchAppBeforePlaying) bringAppForeground(foregroundApp);
    });

    NSError *runError = nil;
    JS_DIAG("P5", "before runScriptAtPath");
    BOOL ok = [runtime runScriptAtPath:filePath bundlePath:scriptBundlePath manifest:currentManifest context:session.taskContext error:&runError];
    JS_DIAG("P6", "runScript returned success=%d total=%.2fms", ok, (CFAbsoluteTimeGetCurrent() - requestAt) * 1000.0);"""

if old_exec_js in sp:
    sp = sp.replace(old_exec_js, new_exec_js)

# Also fix the call for repeatTime replay
old_replay_js = """        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), _jsSerialQueue, ^{
            [self executeJSIteration:session filePath:filePath foregroundApp:foregroundApp];
        });"""

new_replay_js = """        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), _jsSerialQueue, ^{
            [self executeJSIteration:session filePath:filePath foregroundApp:foregroundApp requestAt:CFAbsoluteTimeGetCurrent()];
        });"""

if old_replay_js in sp:
    sp = sp.replace(old_replay_js, new_replay_js)

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/ScriptPlayer.xm", "w", encoding="utf-8") as f:
    f.write(sp)

# 2. UPDATE TLinkautoJSRuntime.mm
with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/TLinkautoJSRuntime.mm", "r", encoding="utf-8") as f:
    rt = f.read()

if '#import "TLinkDiagnostic.h"' not in rt:
    rt = rt.replace('#import "TLinkautoJSRuntime.h"', '#import "TLinkautoJSRuntime.h"\n#import "TLinkDiagnostic.h"')

old_run = """- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest context:(TLinkTaskExecutionContext *)context error:(NSError **)error
{
    if (_running) {"""

new_run = """- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest context:(TLinkTaskExecutionContext *)context error:(NSError **)error
{
    CFAbsoluteTime runtimeStart = CFAbsoluteTimeGetCurrent();
    #define RUNTIME_DIAG(checkpoint, message) JS_DIAG(checkpoint, "%s elapsed=%.2fms", message, (CFAbsoluteTimeGetCurrent() - runtimeStart) * 1000.0)
    RUNTIME_DIAG("R0", "enter runScriptAtPath");

    if (_running) {"""

if old_run in rt:
    rt = rt.replace(old_run, new_run)

# Next diagnostics R1, R2, R3, R4, R5, R6, R7, R8
old_diag2 = """    [self prepareConsoleLogFiles];
    
    os_unfair_lock_lock(&_logStateLock);
    _acceptingLogs = YES;
    os_unfair_lock_unlock(&_logStateLock);
    
    os_unfair_lock_lock(&_handlesLock);
    _acceptingHandles = YES;
    os_unfair_lock_unlock(&_handlesLock);
    
    _cancelState->aborted.store(false, std::memory_order_release);
    
    @try {

    NSLog(@"[Diag-E1] Init JSVM start");
    JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
    NSLog(@"[Diag-E2] Init JSVM done, Init JSContext start");
    JSContext *context = [[JSContext alloc] initWithVirtualMachine:vm];
    _context = context;
    NSLog(@"[Diag-E3] Init JSContext done");"""

new_diag2 = """    [self prepareConsoleLogFiles];
    RUNTIME_DIAG("R1", "openLog finished");
    
    os_unfair_lock_lock(&_logStateLock);
    _acceptingLogs = YES;
    os_unfair_lock_unlock(&_logStateLock);
    
    os_unfair_lock_lock(&_handlesLock);
    _acceptingHandles = YES;
    os_unfair_lock_unlock(&_handlesLock);
    
    _cancelState->aborted.store(false, std::memory_order_release);
    
    @try {

    NSLog(@"[Diag-E1] Init JSVM start");
    JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
    RUNTIME_DIAG("R2", "JSVirtualMachine created");
    NSLog(@"[Diag-E2] Init JSVM done, Init JSContext start");
    JSContext *context = [[JSContext alloc] initWithVirtualMachine:vm];
    RUNTIME_DIAG("R3", "JSContext created");
    _context = context;
    NSLog(@"[Diag-E3] Init JSContext done");"""

if old_diag2 in rt:
    rt = rt.replace(old_diag2, new_diag2)


old_diag3 = """    __weak TLinkautoJSRuntime *weakSelf = self;
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        NSLog(@"com.tlinkauto.jsruntime: exception: %@", exception);
        ctx.exception = exception;
        TLinkautoJSRuntime *strongSelf = weakSelf;
        if (strongSelf) [strongSelf appendConsoleLogWithLevel:@"error" message:[exception toString]];
    };

    [self attachBridgesToContext:context];"""

new_diag3 = """    __weak TLinkautoJSRuntime *weakSelf = self;
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        NSLog(@"com.tlinkauto.jsruntime: exception: %@", exception);
        ctx.exception = exception;
        TLinkautoJSRuntime *strongSelf = weakSelf;
        if (strongSelf) [strongSelf appendConsoleLogWithLevel:@"error" message:[exception toString]];
    };
    RUNTIME_DIAG("R4", "exception handler installed");

    [self attachBridgesToContext:context];
    RUNTIME_DIAG("R5", "bridge installed");"""

if old_diag3 in rt:
    rt = rt.replace(old_diag3, new_diag3)


old_diag4 = """    [context evaluateScript:helperPrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://helper-prelude.js"]];
    NSURL *sourceURL = [NSURL fileURLWithPath:scriptPath ?: @"script.js"];
    NSLog(@"[Diag-E5] Evaluating main script");
    [context evaluateScript:script withSourceURL:sourceURL];
    NSLog(@"[Diag-E6] Script evaluation finished");
    BOOL success = !context.exception && ![self isAborted];"""

new_diag4 = """    [context evaluateScript:helperPrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://helper-prelude.js"]];
    RUNTIME_DIAG("R6", "bootstrap evaluated");
    NSURL *sourceURL = [NSURL fileURLWithPath:scriptPath ?: @"script.js"];
    NSLog(@"[Diag-E5] Evaluating main script");
    RUNTIME_DIAG("R7", "before user evaluate");
    [context evaluateScript:script withSourceURL:sourceURL];
    RUNTIME_DIAG("R8", "after user evaluate");
    NSLog(@"[Diag-E6] Script evaluation finished");
    BOOL success = !context.exception && ![self isAborted];"""

if old_diag4 in rt:
    rt = rt.replace(old_diag4, new_diag4)


with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/TLinkautoJSRuntime.mm", "w", encoding="utf-8") as f:
    f.write(rt)

print("Diagnostics injected into sp and rt")
