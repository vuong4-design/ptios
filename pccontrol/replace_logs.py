import sys

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/TLinkautoJSRuntime.mm", "r", encoding="utf-8") as f:
    content = f.read()

# Add E1, E2, E3
old_init_vm = """    @try {

    JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
    JSContext *context = [[JSContext alloc] initWithVirtualMachine:vm];
    _context = context;"""

new_init_vm = """    @try {

    NSLog(@"[Diag-E1] Init JSVM start");
    JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
    NSLog(@"[Diag-E2] Init JSVM done, Init JSContext start");
    JSContext *context = [[JSContext alloc] initWithVirtualMachine:vm];
    _context = context;
    NSLog(@"[Diag-E3] Init JSContext done");"""

if old_init_vm in content:
    content = content.replace(old_init_vm, new_init_vm)

# Add E4, E5, E6, E7
old_eval = """    [self installWatchdogForContext:context];
    [context evaluateScript:consolePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://console-prelude.js"]];
    [context evaluateScript:modulePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://module-prelude.js"]];
    [context evaluateScript:helperPrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://helper-prelude.js"]];
    NSURL *sourceURL = [NSURL fileURLWithPath:scriptPath ?: @"script.js"];
    [context evaluateScript:script withSourceURL:sourceURL];
    BOOL success = !context.exception && ![self isAborted];"""

new_eval = """    [self installWatchdogForContext:context];
    NSLog(@"[Diag-E4] Evaluating prelude");
    [context evaluateScript:consolePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://console-prelude.js"]];
    [context evaluateScript:modulePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://module-prelude.js"]];
    [context evaluateScript:helperPrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://helper-prelude.js"]];
    NSURL *sourceURL = [NSURL fileURLWithPath:scriptPath ?: @"script.js"];
    NSLog(@"[Diag-E5] Evaluating main script");
    [context evaluateScript:script withSourceURL:sourceURL];
    NSLog(@"[Diag-E6] Script evaluation finished");
    BOOL success = !context.exception && ![self isAborted];"""

if old_eval in content:
    content = content.replace(old_eval, new_eval)

# Add E8
old_finally = """    } @finally {
        [self releaseOwnedHandles];
        [self clearWatchdogForContext:_context];
        _context = nil;"""

new_finally = """    } @finally {
        NSLog(@"[Diag-E8] Teardown start");
        [self releaseOwnedHandles];
        [self clearWatchdogForContext:_context];
        _context = nil;"""

if old_finally in content:
    content = content.replace(old_finally, new_finally)

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/TLinkautoJSRuntime.mm", "w", encoding="utf-8") as f:
    f.write(content)
print("Updated logs!")
