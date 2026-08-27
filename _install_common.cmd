rem Shared between install.cmd and install-copilot.cmd: locating a Python
rem interpreter and building vulnhunter-fix's bundled venv. This file is
rem never invoked directly -- callers jump straight to a label in it:
rem
rem   call "%SCRIPT_DIR%\_install_common.cmd" :build_vulnfix_venv "%dst%"
rem
rem which starts execution at that label without running anything above it
rem (this is a standard cmd.exe "batch library" pattern: CALL with a label
rem argument to another .cmd file runs from that label, and a bare
rem "call :otherlabel" issued while executing there resolves against this
rem file, not the original caller). Callers must set INSTALL_INVOCATION
rem before calling :build_vulnfix_venv -- used only in one error message,
rem so it names whichever script the user actually ran.
rem
rem NOTE: written and reviewed on macOS, not run against real cmd.exe --
rem verify this file's calling convention before relying on it.

:build_vulnfix_venv
setlocal EnableDelayedExpansion
set "skill_dir=%~1"
set "venv=%skill_dir%\.venv"

set "PYEXE="
call :find_python
if "%PYEXE%"=="" (
    echo error: python 3.11+ not found ^(needed for vulnhunter-fix's bundled venv^). 1>&2
    echo install Python 3.11+ from https://www.python.org/downloads/ and re-run !INSTALL_INVOCATION!. 1>&2
    endlocal & exit /b 1
)

if exist "%venv%\" (
    rmdir /s /q "%venv%"
)
echo   creating bundled venv with %PYEXE%
rem Note: interpreter/launcher failures can exit with large negative codes,
rem which "if errorlevel N" misreads as success. Check !ERRORLEVEL! for
rem exact equality to 0 instead.
call %PYEXE% -m venv "%venv%"
if not !ERRORLEVEL!==0 (
    echo error: failed to create venv at %venv% 1>&2
    endlocal & exit /b 1
)

rem Pin must stay in sync with _install_common.sh's VULNFIX_DEPS (shared by
rem install.sh and install-copilot.sh) and preflight.py's REQ-GRA-001 -- CI
rem enforces this via vulnhunt-copilot/scripts/check_dep_pins_consistent.py.
set VULNFIX_DEPS="jsonschema>=4.18" "graphifyy>=0.8.14,<0.9.0"

"%venv%\Scripts\python.exe" -m pip install --quiet --disable-pip-version-check --upgrade pip
if not !ERRORLEVEL!==0 (
    echo error: failed to upgrade pip in %venv% 1>&2
    endlocal & exit /b 1
)
echo   installing runtime deps into venv: %VULNFIX_DEPS%
"%venv%\Scripts\python.exe" -m pip install --quiet --disable-pip-version-check %VULNFIX_DEPS%
if not !ERRORLEVEL!==0 (
    echo error: failed to install bundled deps into %venv% 1>&2
    endlocal & exit /b 1
)

rem Smoke test: run the venv's own interpreter directly (not %PYEXE%) so
rem this tests the venv contents without depending on _skill_bootstrap's
rem re-exec mechanism.
"%venv%\Scripts\python.exe" -c "import jsonschema, graphify" >nul 2>&1
if not !ERRORLEVEL!==0 (
    echo error: bootstrap smoke test failed -- venv built but jsonschema/graphify not importable. 1>&2
    echo        check %venv%\Lib\site-packages\ 1>&2
    endlocal & exit /b 1
)
echo   bundled venv ready: %venv%
endlocal & exit /b 0

:find_python
rem Prefer the py launcher pinned to 3.11 (graphifyy ships per-minor wheels
rem and 3.11 is the reference minor); otherwise accept any interpreter that
rem satisfies pyproject's requires-python (>=3.11).
rem Note: some launcher/interpreter failures exit with large negative codes
rem (e.g. "py -3.11" when 3.11 isn't installed), which "if errorlevel N"
rem misreads as success since it compares signed integers against N. Check
rem !ERRORLEVEL! for exact equality to 0 instead.
where py >nul 2>nul
if !ERRORLEVEL!==0 (
    py -3.11 -c "import sys" >nul 2>nul
    if !ERRORLEVEL!==0 (
        set "PYEXE=py -3.11"
        exit /b 0
    )
)
for %%C in (python3.13 python3.12 python3.11 python) do (
    where %%C >nul 2>nul
    if !ERRORLEVEL!==0 (
        %%C -c "import sys; sys.exit(0 if sys.version_info[:2] >= (3,11) else 1)" >nul 2>nul
        if !ERRORLEVEL!==0 (
            set "PYEXE=%%C"
            exit /b 0
        )
    )
)
exit /b 0
