@echo off
setlocal EnableDelayedExpansion

rem USERPROFILE guard: destinations (and the rmdir below) derive from
rem USERPROFILE. An unset USERPROFILE would turn deletes into operations on
rem a bad root path -- refuse cleanly.
if "%USERPROFILE%"=="" (
    echo error: USERPROFILE unset -- refusing to run install.cmd 1>&2
    exit /b 1
)

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "SKILLS_PARENT=%USERPROFILE%\.claude\skills"

rem :find_python/:build_vulnfix_venv are shared with install-copilot.cmd
rem (both build the same bundled venv for vulnhunter-fix) -- see
rem _install_common.cmd for why this is a separate file rather than
rem duplicated in both scripts.
set "INSTALL_INVOCATION=install.cmd"
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

echo.
if "%installed_any%"=="1" (
    echo To update after pulling changes: re-run install.cmd
    echo To uninstall: "%SCRIPT_DIR%\uninstall.cmd"
) else (
    echo No skills were installed.
)

endlocal
exit /b 0

:install_one
setlocal
set "name=%~1"
set "src=%SCRIPT_DIR%\%name%"
set "dst=%SKILLS_PARENT%\%name%"

if not exist "%src%\SKILL.md" (
    if "%name%"=="vulnhunt" (
        echo Error: SKILL.md not found at %src% 1>&2
        echo Make sure you are running this script from the repository root. 1>&2
        endlocal & exit /b 1
    ) else (
        echo Skipping %name% -- %src%\SKILL.md not present on this branch.
        endlocal & exit /b 0
    )
)

rem Handle an existing destination (junction/symlink or plain directory).
if exist "%dst%\" (
    echo Removing old copy of %name%...
    rmdir /s /q "%dst%"
)

rem Copy files (not a symlink/junction -- links break find/glob in subagents).
robocopy "%src%" "%dst%" /E /NFL /NDL /NJH /NJS >nul
if errorlevel 8 (
    echo error: failed to copy %src% to %dst% 1>&2
    endlocal & exit /b 1
)

rem Record the source commit so a skill's staleness check (e.g.
rem vulnhunter-fix SKILL.md Step 0b) can compare the installed copy against
rem upstream main. Best-effort: skipped outside a git checkout.
git -C "%SCRIPT_DIR%" rev-parse HEAD > "%dst%\.installed-from" 2>nul
echo Installed %name% (copied to %dst%)

rem vulnhunter-fix ships a Python package whose runtime deps (jsonschema,
rem graphifyy) must live in a bundled venv that scripts\_skill_bootstrap.py
rem loads. The other skills are prompt-only and need no venv.
if "%name%"=="vulnhunter-fix" (
    call "%SCRIPT_DIR%\_install_common.cmd" :build_vulnfix_venv "%dst%"
    if errorlevel 1 (
        endlocal & exit /b 1
    )
)

endlocal & set "installed_any=1" & exit /b 0
