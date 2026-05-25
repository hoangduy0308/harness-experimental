@echo off
setlocal

rem Windows launcher for the durable Harness CLI.
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.." >nul || exit /b 1
set "REPO_ROOT=%CD%"
popd >nul

if not defined HARNESS_REPO_ROOT set "HARNESS_REPO_ROOT=%REPO_ROOT%"

if not defined HARNESS_DB set "HARNESS_DB=%REPO_ROOT%\harness.db"

if defined HARNESS_RUST_CLI (
  set "RUST_CLI=%HARNESS_RUST_CLI%"
) else if exist "%SCRIPT_DIR%bin\harness-cli.exe" (
  set "RUST_CLI=%SCRIPT_DIR%bin\harness-cli.exe"
) else (
  set "RUST_CLI=%REPO_ROOT%\target\debug\harness-cli.exe"
)

if not exist "%RUST_CLI%" (
  echo Error: Harness Rust CLI not found: %RUST_CLI% 1>&2
  echo Install Harness again or build it with: cargo build --package harness-cli 1>&2
  exit /b 127
)

"%RUST_CLI%" %*
exit /b %ERRORLEVEL%
