import sys

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/Task.xm", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add headers
if "#import <Foundation/Foundation.h>" not in content:
    content = content.replace('#include "Task.h"', '#include "Task.h"\n#import <Foundation/Foundation.h>\n#include <spawn.h>\n#include <poll.h>')

# 2. Fix block capture issue
old_block_dispatch = """    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(outPipe[0], NO); });
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(errPipe[0], YES); });"""

new_block_dispatch = """    int outFd = outPipe[0];
    int errFd = errPipe[0];
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(outFd, NO); });
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(errFd, YES); });"""

if old_block_dispatch in content:
    content = content.replace(old_block_dispatch, new_block_dispatch)

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/Task.xm", "w", encoding="utf-8") as f:
    f.write(content)
print("Fixed Task.xm")
