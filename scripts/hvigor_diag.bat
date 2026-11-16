@echo off
rem Copyright (C) 2026 MC4HOS Contributors
rem SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
rem
rem Diagnostic runner: executes an arbitrary hvigorw task/args against the
rem locally installed DevEco Studio toolchain.
rem   hvigor_diag.bat tasks
rem   hvigor_diag.bat --mode module -p module=entry@default assembleHap
setlocal
set "ROOT=%~dp0.."
if not defined DEVECO_STUDIO_HOME set "DEVECO_STUDIO_HOME=C:\Program Files\Huawei\DevEco Studio"
if not exist "%DEVECO_STUDIO_HOME%\tools\hvigor\bin\hvigorw.js" (
  echo ERROR: DevEco Studio not found at "%DEVECO_STUDIO_HOME%"
  exit /b 1
)
set "NODE=%DEVECO_STUDIO_HOME%\tools\node\node.exe"
set "HVIGORW_JS=%DEVECO_STUDIO_HOME%\tools\hvigor\bin\hvigorw.js"
set "DEVECO_SDK_HOME=%DEVECO_STUDIO_HOME%\sdk"
cd /d "%ROOT%"
call "%NODE%" "%HVIGORW_JS%" %*
endlocal
