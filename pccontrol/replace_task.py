import sys

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/Task.xm", "r", encoding="utf-8") as f:
    content = f.read()

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/TaskReplacement.mm.scratch", "r", encoding="utf-8") as f:
    replacement = f.read()

# Replace part 1
marker1_start = "// === runShell drain/timeout support (Group A) ==="
marker1_end = "    int taskType = getTaskType(buff);"

if marker1_start in content and marker1_end in content:
    idx1 = content.find(marker1_start)
    idx2 = content.find(marker1_end) + len(marker1_end)
    content = content[:idx1] + replacement + content[idx2:]

# Replace part 2
marker2_start = "    else if (taskType == TASK_RUN_SHELL)"
marker2_end = "    else if (taskType == TASK_TOUCH_RECORDING_START)"

if marker2_start in content and marker2_end in content:
    idx3 = content.find(marker2_start)
    idx4 = content.find(marker2_end)
    
    task_run_shell_code = """    else if (taskType == TASK_RUN_SHELL)
    {
        @autoreleasepool{
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
            
            TLinkShellResult *result = RunShellCore(command, context, timeout, SIZE_MAX);
            
            NSString *combined = result.stderrStr.length > 0 ? [result.stdoutStr stringByAppendingString:result.stderrStr] : result.stdoutStr;
            NSString *safeOutput = [[combined stringByReplacingOccurrencesOfString:@"\\r" withString:@"\\\\r"] stringByReplacingOccurrencesOfString:@"\\n" withString:@"\\\\n"];
            if (result.stdoutTruncated || result.stderrTruncated) {
                safeOutput = [safeOutput stringByAppendingFormat:@"\\\\n[output truncated: exceeded %lu bytes]", (unsigned long)kShellMaxCapturedOutputBytes];
            }
            
            if (result.timedOut) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command timed out after %.0fs: %@\\r\\n", timeout, safeOutput] UTF8String], writeStreamRef);
            } else if (result.cancelled) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command cancelled: %@\\r\\n", safeOutput] UTF8String], writeStreamRef);
            } else if (result.exitCode == 0) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\\r\\n", safeOutput] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command failed (%d): %@\\r\\n", result.exitCode, safeOutput] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_RUN_SHELL_V2)
    {
        @autoreleasepool{
            NSError *jsonErr = nil;
            NSData *payloadData = [NSData dataWithBytes:eventData length:actualLength - 2];
            NSDictionary *req = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:&jsonErr];
            
            NSString *command = @"";
            double timeout = kShellDefaultTimeout;
            NSUInteger maxOutput = kTLinkautoJSMaxResponseBytes;
            
            if (!jsonErr && [req isKindOfClass:[NSDictionary class]]) {
                command = req[@"command"] ?: @"";
                if (req[@"timeoutSeconds"]) timeout = [req[@"timeoutSeconds"] doubleValue];
                if (req[@"maxOutputBytes"]) maxOutput = [req[@"maxOutputBytes"] unsignedIntegerValue];
            }
            
            TLinkShellResult *result = RunShellCore(command, context, timeout, maxOutput);
            
            NSMutableDictionary *resp = [NSMutableDictionary dictionary];
            resp[@"exitCode"] = result.exitCode == -1 ? [NSNull null] : @(result.exitCode);
            resp[@"terminationSignal"] = @(result.terminationSignal);
            resp[@"timedOut"] = @(result.timedOut);
            resp[@"cancelled"] = @(result.cancelled);
            resp[@"drainForcedClosed"] = @(result.drainForcedClosed);
            resp[@"stdout"] = result.stdoutStr;
            resp[@"stderr"] = result.stderrStr;
            resp[@"stdoutTruncated"] = @(result.stdoutTruncated);
            resp[@"stderrTruncated"] = @(result.stderrTruncated);
            
            NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
            if (respData.length > kTLinkautoJSMaxResponseBytes) {
                resp[@"stdout"] = @"[Truncated due to JSON size limit]";
                resp[@"stderr"] = @"[Truncated due to JSON size limit]";
                resp[@"stdoutTruncated"] = @(YES);
                resp[@"stderrTruncated"] = @(YES);
                respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
            }
            
            NSString *respJson = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\\r\\n", respJson] UTF8String], writeStreamRef);
        }
    }
"""
    content = content[:idx3] + task_run_shell_code + content[idx4:]

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/Task.xm", "w", encoding="utf-8") as f:
    f.write(content)
print("Done!")
