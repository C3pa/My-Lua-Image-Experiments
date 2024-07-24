# Introduction

This module implements conversion functions between okhsv and sRGB color spaces as described in the following blog posts:

- https://bottosson.github.io/posts/colorpicker/
- https://bottosson.github.io/posts/gamutclipping/
- https://bottosson.github.io/posts/oklab/

# Usage


There is `init.lua` that loads compiled `dll` and defines some wrapper Lua functions for easier usage.

```lua
local oklab = require("livecoding.oklab")
```

# Building

To build this module you will need a C++ compiler. I used MSYS2 distribution of GCC.

To start the 32-bit bash on 64-bit Windows run the following command in CMD:
```bat
C:\\msys64\\mingw32.exe bash
```

Then navigate this folder. To compile, run the following two commands in bash:
```sh
cd /d/GOG/MWSE Dev/Data Files/MWSE/mods/livecoding/oklab/src
gcc -c liboklab.cpp -o liboklab.o
gcc -shared -o liboklab.dll liboklab.o


gcc -c libhsv.cpp -o libhsv.o
gcc -shared -o libhsv.dll libhsv.o
```
