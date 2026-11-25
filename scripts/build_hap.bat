@echo off
rem Copyright (C) 2026 MC4HOS Contributors
rem SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
rem
rem This Source Code Form is subject to the terms of the Mozilla Public
rem License, v. 2.0. If a copy of the MPL was not distributed with this
rem file, You can obtain one at https://mozilla.org/MPL/2.0/.

rem Builds the HAP locally, using the DevEco Studio installation on this
rem machine. Runtime packs are fetched at build time and bundled inside the
rem HAP; set BUNDLE_JRES=0 to build without them. The pinned LWJGL/OpenAL stack
rem must already be staged by scripts\native\build_stack.sh.
rem
rem Override the install location with:  set DEVECO_STUDIO_HOME=<dir>
setlocal enabledelayedexpansion

set "ROOT=%~dp0.."

rem --- locate DevEco Studio ------------------------------------------------
if not defined DEVECO_STUDIO_HOME set "DEVECO_STUDIO_HOME=C:\Program Files\Huawei\DevEco Studio"
if not exist "%DEVECO_STUDIO_HOME%\tools\hvigor\bin\hvigorw.js" (
  echo ERROR: DevEco Studio not found at "%DEVECO_STUDIO_HOME%"
  echo        Set DEVECO_STUDIO_HOME to your install directory and retry.
  exit /b 1
)
echo DevEco Studio: %DEVECO_STUDIO_HOME%

set "NODE=%DEVECO_STUDIO_HOME%\tools\node\node.exe"
set "HVIGORW_JS=%DEVECO_STUDIO_HOME%\tools\hvigor\bin\hvigorw.js"
set "DEVECO_SDK_HOME=%DEVECO_STUDIO_HOME%\sdk"

rem --- dependencies --------------------------------------------------------
if exist "%DEVECO_STUDIO_HOME%\tools\ohpm\bin\ohpm.bat" (
  echo Running ohpm install...
  call "%DEVECO_STUDIO_HOME%\tools\ohpm\bin\ohpm.bat" install
  if errorlevel 1 (
    echo ERROR: ohpm install failed
    exit /b 1
  )
) else (
  echo [warn] ohpm not found under tools\ohpm - skipping dependency install
)

rem --- bundled runtimes -----------------------------------------------------
cd /d "%ROOT%"
if not "%BUNDLE_JRES%"=="0" (
  echo Fetching bundled Java runtimes ^(set BUNDLE_JRES=0 to skip^)...
  python "%ROOT%\scripts\fetch_bundled_jres.py" --dest "%ROOT%\entry\src\main\resources\rawfile\jvm"
  if errorlevel 1 (
    echo ERROR: bundled runtime fetch failed
    exit /b 1
  )
  echo Packaging JRE native libraries into entry\libs ...
  python "%ROOT%\scripts\bundle_jre_natives.py"
  if errorlevel 1 (
    echo ERROR: JRE native packaging failed
    exit /b 1
  )
)

echo Building MC4HOS bridge jar...
python "%ROOT%\scripts\build_bridge_jar.py"
if errorlevel 1 (
  echo ERROR: bridge jar build failed
  exit /b 1
)

echo Verifying staged native stack...
python "%ROOT%\scripts\check_native_stack.py" --entry "%ROOT%\entry"
if errorlevel 1 (
  echo ERROR: native stack validation failed
  exit /b 1
)

rem --- build ---------------------------------------------------------------
echo Building HAP ^(debug, unsigned^)...
if not exist "%ROOT%\.build" mkdir "%ROOT%\.build"
set "BUILD_LOG=%ROOT%\.build\hvigor-build.log"
call "%NODE%" "%HVIGORW_JS%" --mode module -p module=entry@default -p product=default assembleHap > "%BUILD_LOG%" 2>&1
set "BUILD_EXIT=%ERRORLEVEL%"
type "%BUILD_LOG%"
if not "%BUILD_EXIT%"=="0" (
  echo ERROR: hvigor exited with %BUILD_EXIT%
  exit /b 1
)
findstr /C:"BUILD FAILED" "%BUILD_LOG%" >nul
if not errorlevel 1 (
  echo ERROR: hvigor reported BUILD FAILED
  exit /b 1
)
findstr /C:"BUILD SUCCESSFUL" "%BUILD_LOG%" >nul
if errorlevel 1 (
  echo ERROR: hvigor produced no BUILD SUCCESSFUL marker
  exit /b 1
)

rem --- collect -------------------------------------------------------------
if not exist out mkdir out
for /r "%ROOT%\entry\build" %%f in (*.hap) do copy /y "%%f" "out\" >nul
echo.
echo Done. HAP file(s):
dir /b "%ROOT%\out\*.hap"
echo Location: %ROOT%\out
endlocal
