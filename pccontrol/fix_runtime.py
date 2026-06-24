import sys

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/TLinkautoJSRuntime.mm", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add #import <os/lock.h> at the top
if "#import <os/lock.h>" not in content:
    content = content.replace('#import "TLinkautoJSRuntime.h"', '#import "TLinkautoJSRuntime.h"\n#import <os/lock.h>')

# 2. Remove OS_UNFAIR_LOCK_INIT in init
content = content.replace("        _logStateLock = OS_UNFAIR_LOCK_INIT;\n", "")
content = content.replace("        _handlesLock = OS_UNFAIR_LOCK_INIT;\n", "")

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/TLinkautoJSRuntime.mm", "w", encoding="utf-8") as f:
    f.write(content)
print("Fixed runtime!")
