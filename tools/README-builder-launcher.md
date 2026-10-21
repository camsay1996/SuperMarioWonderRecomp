# Wonder tools for Windows: Builder and Launcher

Source only. These tools contain no game files, keys, firmware or builds. You need your own legally dumped copy of
Super Mario Bros. Wonder 1.0.0.

## Builder (`tools\builder\Wonder Builder.bat`)
Checks the build prerequisites and installs only the missing ones with winget, with a live log:
Visual Studio C++ and Clang tools, CMake, Ninja, Python 3.11+ and the project venv, Vulkan SDK 1.4.357+, .NET SDK 10.
Installing may need administrator rights and several GB of downloads. The game build itself is not in the builder yet.

## Launcher (`tools\launcher\Wonder Launcher.bat`)
Starts `private\wonder\build\wonder.exe` with startup options: display (fullscreen, handheld or docked, ultrawide),
graphics (GPU, pipelined submits), FSR upscaling, a 30 fps limit, mute, language, and a live log of the game.
Options apply at launch. Controller mapping and DLSS are not available.

Both are PowerShell window apps: double-click the `.bat`. Run the `.ps1` with
`powershell -NoProfile -ExecutionPolicy Bypass -STA -File <script>` to see error messages.

Developed with AI assistance from Claude (Anthropic).
