@echo off
setlocal EnableDelayedExpansion

rem USERPROFILE guard: destinations (and the rmdir below) derive from
rem USERPROFILE. An unset USERPROFILE would turn deletes into operations on
rem a bad root path -- refuse cleanly.
if "%USERPROFILE%"=="" (
    echo error: USERPROFILE unset -- refusing to run install-copilot.cmd 1>&2
    exit /b 1
)

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "SKILLS_PARENT=%USERPROFILE%\.copilot\skills"

rem :find_python/:build_vulnfix_venv are shared with install.cmd (both
rem build the same bundled venv for vulnhunter-fix) -- see
rem _install_common.cmd for why this is a separate file rather than
rem duplicated in both scripts.
set "INSTALL_INVOCATION=install-copilot.cmd"
if not exist "%SCRIPT_DIR%\_install_common.cmd" (
    echo Error: %SCRIPT_DIR%\_install_common.cmd not found. 1>&2
    echo Make sure you are running this script from the repository root. 1>&2
    exit /b 1
)

if not exist "%SKILLS_PARENT%" (
    echo Creating directory %SKILLS_PARENT%
    mkdir "%SKILLS_PARENT%"
)

set "installed_any=0"
for %%S in (vulnhunt vulnhunt-fix-verify vulnhunter-fix) do (
    call :install_one "%%S"
    if errorlevel 1 exit /b 1
)

if "%installed_any%"=="1" call :configure_git_bash_terminal

echo.
if "%installed_any%"=="1" (
    echo These are Copilot Agent Skills: VS Code, JetBrains, and GitHub Copilot
    echo CLI all auto-discover them from %%USERPROFILE%%\.copilot\skills\ -- no
    echo further configuration needed.
    echo.
    echo Next steps:
    echo 1. Open the repo you want to scan/fix in your editor.
    echo 2. Open Copilot Chat, switch to Agent mode.
    echo 3. Run: /vulnhunt   ^(scanner^)
    echo    or:  /vulnhunter-fix   ^(fixer, run after a scan^)
    echo    or:  /vulnhunt-fix-verify   ^(independent fix verifier^)
    echo.
    echo To update after pulling changes: re-run install-copilot.cmd
    echo To uninstall: "%SCRIPT_DIR%\uninstall-copilot.cmd"
) else (
    echo No skills were installed.
)

endlocal
exit /b 0

:install_one
setlocal EnableDelayedExpansion
set "name=%~1"
set "base=%SCRIPT_DIR%\%name%"
set "overlay=%SCRIPT_DIR%\vulnhunt-copilot\skills\%name%"
set "dst=%SKILLS_PARENT%\%name%"

if not exist "%base%\SKILL.md" (
    if "%name%"=="vulnhunt" (
        echo Error: base skill not found at %base% 1>&2
        echo Make sure you are running this script from the repository root. 1>&2
        endlocal & exit /b 1
    ) else (
        echo Skipping %name% -- %base%\SKILL.md not present on this branch.
        endlocal & exit /b 0
    )
)
if not exist "%overlay%\" (
    echo Error: Copilot overlay not found at %overlay% 1>&2
    echo Make sure you are running this script from the repository root. 1>&2
    endlocal & exit /b 1
)

if exist "%dst%\" (
    echo Removing old copy of %name%...
    rmdir /s /q "%dst%"
)

rem Each skill is assembled from two sources: the existing Claude Code
rem skill directory (base, unmodified) and vulnhunt-copilot\skills\%name%
rem (overlay, only the files that differ for Copilot). Copying base then
rem overlay on top means vulnhunter-fix's Python package and test suite
rem exist exactly once in the repo, shared by both platforms.
robocopy "%base%" "%dst%" /E /NFL /NDL /NJH /NJS >nul
if errorlevel 8 (
    echo error: failed to copy %base% to %dst% 1>&2
    endlocal & exit /b 1
)
rem The base directory's own README.md documents the Claude Code skill --
rem leaving it in the installed Copilot skill folder would be actively
rem misleading. SKILL.md (the actual functional entry point) is unaffected.
if exist "%dst%\README.md" del /q "%dst%\README.md"
robocopy "%overlay%" "%dst%" /E /NFL /NDL /NJH /NJS >nul
if errorlevel 8 (
    echo error: failed to copy %overlay% to %dst% 1>&2
    endlocal & exit /b 1
)

rem vulnhunt-fix-verify references verify_disposition.schema.json, which
rem lives in vulnhunter-agent\ today rather than in either skill's own
rem tree -- copy it in from its real location instead of duplicating it a
rem second time inside the overlay directory.
if "%name%"=="vulnhunt-fix-verify" (
    copy /y "%SCRIPT_DIR%\vulnhunter-agent\verify_disposition.schema.json" "%dst%\verify_disposition.schema.json" >nul
)

git -C "%SCRIPT_DIR%" rev-parse HEAD > "%dst%\.installed-from" 2>nul
echo Installed %name% (copied to %dst%)

if "%name%"=="vulnhunter-fix" (
    rem A handful of base files need small, well-defined text substitutions
    rem (attribution trailers, a few tool-name mentions in comments) rather
    rem than a full duplicate overlay copy -- see apply_substitutions.py for
    rem why and exactly what changes. Fails loudly if upstream wording has
    rem drifted since the substitution list was written.
    set "PYEXE="
    call "%SCRIPT_DIR%\_install_common.cmd" :find_python
    if "!PYEXE!"=="" (
        echo error: python3.11+ not found ^(needed to apply Copilot text substitutions^). 1>&2
        endlocal & exit /b 1
    )
    call !PYEXE! "%SCRIPT_DIR%\vulnhunt-copilot\scripts\apply_substitutions.py" "%dst%"
    if not !ERRORLEVEL!==0 (
        echo error: failed to apply Copilot text substitutions to %dst% 1>&2
        endlocal & exit /b 1
    )
    call "%SCRIPT_DIR%\_install_common.cmd" :build_vulnfix_venv "%dst%"
    if errorlevel 1 (
        endlocal & exit /b 1
    )
)

endlocal & set "installed_any=1" & exit /b 0

:configure_git_bash_terminal
setlocal EnableDelayedExpansion
rem The skills embed bash syntax in their code blocks. VS Code Copilot's
rem agent terminal tool defaults to whatever the workspace's default
rem terminal profile is -- normally PowerShell or cmd.exe on Windows,
rem neither of which understands that syntax. Point Copilot's agent
rem terminal specifically at Git Bash (chat.tools.terminal.terminalProfile.windows),
rem without touching the user's regular terminal default. Best-effort:
rem skip quietly (with instructions) if Git Bash isn't found, or if the
rem PowerShell step reports it couldn't proceed safely.
set "GITBASH="
for %%G in (
    "%ProgramFiles%\Git\bin\bash.exe"
    "%ProgramFiles(x86)%\Git\bin\bash.exe"
    "%LocalAppData%\Programs\Git\bin\bash.exe"
) do (
    if not "!GITBASH!"=="" goto :gitbash_found
    if exist %%G set "GITBASH=%%~G"
)
:gitbash_found

if "%GITBASH%"=="" (
    echo.
    echo Note: Git Bash not found at common install locations -- skipping
    echo automatic Copilot terminal profile setup. Install Git for Windows
    echo ^(https://git-scm.com/download/win^), or set this yourself in VS
    echo Code settings.json:
    echo   "chat.tools.terminal.terminalProfile.windows": { "path": "C:\\Program Files\\Git\\bin\\bash.exe" }
    endlocal & exit /b 0
)

echo.
echo Configuring Copilot's agent terminal to use Git Bash (%GITBASH%)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\vulnhunt-copilot\scripts\windows\configure-terminal-profile.ps1" -GitBashPath "%GITBASH%"

endlocal & exit /b 0
