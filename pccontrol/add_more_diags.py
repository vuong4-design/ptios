import sys

# IPCMessagePort.xm
with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/IPCMessagePort.xm", "r", encoding="utf-8") as f:
    ipc = f.read()

if '#import "TLinkDiagnostic.h"' not in ipc:
    ipc = ipc.replace('#include "IPCMessagePort.h"', '#include "IPCMessagePort.h"\n#import "TLinkDiagnostic.h"')

old_ipc = """            CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
            NSLog(@"### com.tlinkauto.springboard: IPC task start: %@", rawTask);
            CFWriteStreamRef responseStream = CFWriteStreamCreateWithAllocatedBuffers(kCFAllocatorDefault,
                                                                                      kCFAllocatorDefault);
            if (responseStream) {
                CFWriteStreamOpen(responseStream);
                processTask((UInt8 *)[rawTask UTF8String], responseStream);"""

new_ipc = """            CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
            NSLog(@"### com.tlinkauto.springboard: IPC task start: %@", rawTask);
            JS_DIAG("S0", "socket packet complete length=%zu", (size_t)[rawTask length]);
            CFWriteStreamRef responseStream = CFWriteStreamCreateWithAllocatedBuffers(kCFAllocatorDefault,
                                                                                      kCFAllocatorDefault);
            if (responseStream) {
                CFWriteStreamOpen(responseStream);
                JS_DIAG("S1", "before processTask");
                processTask((UInt8 *)[rawTask UTF8String], responseStream);
                JS_DIAG("S2", "after processTask");"""

if old_ipc in ipc:
    ipc = ipc.replace(old_ipc, new_ipc)

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/IPCMessagePort.xm", "w", encoding="utf-8") as f:
    f.write(ipc)


# Task.xm
with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/Task.xm", "r", encoding="utf-8") as f:
    task = f.read()

if '#import "TLinkDiagnostic.h"' not in task:
    task = task.replace('#include "Task.h"', '#include "Task.h"\n#import "TLinkDiagnostic.h"')

old_task0 = """void processTaskWithContext(UInt8 *buff, size_t actualLength, CFWriteStreamRef writeStreamRef, TLinkTaskExecutionContext *context)
{
    if (!buff) return;
    
    //NSLog(@"### com.tlinkauto.springboard: task type: %d. Data: %s", getTaskType(buff), buff);
    UInt8 *eventData = buff + 0x2;
    int taskType = getTaskType(buff);"""

new_task0 = """void processTaskWithContext(UInt8 *buff, size_t actualLength, CFWriteStreamRef writeStreamRef, TLinkTaskExecutionContext *context)
{
    if (!buff) return;
    
    //NSLog(@"### com.tlinkauto.springboard: task type: %d. Data: %s", getTaskType(buff), buff);
    UInt8 *eventData = buff + 0x2;
    int taskType = getTaskType(buff);
    JS_DIAG("T0", "processTask enter type=%d length=%zu", taskType, actualLength);"""

if old_task0 in task:
    task = task.replace(old_task0, new_task0)

old_task1 = """    else if (taskType == TASK_PLAY_SCRIPT)
    {
        @autoreleasepool {
            NSError *err = nil;
            playScript((UInt8*)eventData, &err);"""

new_task1 = """    else if (taskType == TASK_PLAY_SCRIPT)
    {
        @autoreleasepool {
            JS_DIAG("T1", "entered JS play task");
            JS_DIAG("T2", "payload parsed path=%s", (char *)eventData ?: "(null)");
            NSError *err = nil;
            JS_DIAG("T4", "before calling ScriptPlayer/playScript");
            playScript((UInt8*)eventData, &err);
            JS_DIAG("T5", "playScript returned");"""

if old_task1 in task:
    task = task.replace(old_task1, new_task1)

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/Task.xm", "w", encoding="utf-8") as f:
    f.write(task)


# ScriptPlayer.xm
with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/ScriptPlayer.xm", "r", encoding="utf-8") as f:
    sp = f.read()

old_sp = """    NSString *infoFilePath = [NSString stringWithFormat:@"%@/info.plist", scriptBundlePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:infoFilePath isDirectory:&isDir]) {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Info.plist not found.\\r\\n"}];
        return -1;
    }
    NSDictionary *scriptInfo = [NSDictionary dictionaryWithContentsOfFile:infoFilePath];
    NSDictionary *manifest = tlinkautoReadManifest(scriptBundlePath);"""

new_sp = """    NSString *infoFilePath = [NSString stringWithFormat:@"%@/info.plist", scriptBundlePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:infoFilePath isDirectory:&isDir]) {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Info.plist not found.\\r\\n"}];
        return -1;
    }
    NSDictionary *scriptInfo = [NSDictionary dictionaryWithContentsOfFile:infoFilePath];
    JS_DIAG("T3A", "before manifest read");
    NSDictionary *manifest = tlinkautoReadManifest(scriptBundlePath);
    JS_DIAG("T3B", "after manifest read, info/manifest populated");"""

if old_sp in sp:
    sp = sp.replace(old_sp, new_sp)

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/ScriptPlayer.xm", "w", encoding="utf-8") as f:
    f.write(sp)

print("Injected S and T diags!")
