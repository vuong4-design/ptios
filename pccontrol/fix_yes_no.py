import sys

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/Task.xm", "r", encoding="utf-8") as f:
    content = f.read()

# Add YES and NO defines
define_str = """#ifndef YES
#define YES true
#endif
#ifndef NO
#define NO false
#endif
"""

if "define YES" not in content:
    content = content.replace('#import <Foundation/Foundation.h>', '#import <Foundation/Foundation.h>\n' + define_str)

with open("c:/Users/ADMIN/Documents/GitHub/ptios/pccontrol/Task.xm", "w", encoding="utf-8") as f:
    f.write(content)
print("Fixed YES and NO")
