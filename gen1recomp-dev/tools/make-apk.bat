@echo off
setlocal EnableExtensions
rem Build a test APK on Windows.
rem Prereqs: git, Java 11+, Android Studio SDK, and zip (Git's usr\bin\zip.exe is fine).
rem
rem   tools\make-apk.bat
rem   tools\make-apk.bat C:\path\to\gen1recomp-dev

set "ROOT=%~dp0.."
if not "%~1"=="" if exist "%~1\" set "ROOT=%~1"
pushd "%ROOT%" || (echo bad repo path & exit /b 1)
set "ROOT=%CD%"
popd

set "APP_NAME=Pokemon Ruby"
set "APP_ID=com.gen1recomp.ruby"
set "VERSION_CODE=1"
set "VERSION_NAME=0.0.0-dev"
set "LOVE_ANDROID_REF=11.5a"
set "OUT_DIR=%ROOT%\dist"
set "WORK=%ROOT%\.love-android"
if defined LOVE_ANDROID_DIR set "WORK=%LOVE_ANDROID_DIR%"
set "LOVE_ZIP=%OUT_DIR%\ruby.love"
set "APK_OUT=%OUT_DIR%\ruby-debug.apk"

where git >nul 2>&1 || (echo install git & exit /b 1)
where zip >nul 2>&1
if errorlevel 1 (
  if exist "%ProgramFiles%\Git\usr\bin\zip.exe" set "PATH=%ProgramFiles%\Git\usr\bin;%PATH%"
)
where zip >nul 2>&1 || (echo install zip ^(Git for Windows usr\bin^) & exit /b 1)

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
if exist "%LOVE_ZIP%" del /f "%LOVE_ZIP%"

if not exist "%ROOT%\assets\generated\ui\" if not exist "%ROOT%\assets\generated\battle\" (
  echo assets\generated is empty. Import the ROM on desktop first, then pack.
  exit /b 1
)
echo == packing %LOVE_ZIP%
pushd "%ROOT%"
zip -r -q "%LOVE_ZIP%" main.lua conf.lua src assets data lib
zip -r -q "%LOVE_ZIP%" assets\generated
popd
if not exist "%LOVE_ZIP%" (echo zip failed & exit /b 1)

if not exist "%WORK%\gradlew.bat" (
  echo == cloning love-android %LOVE_ANDROID_REF%
  if exist "%WORK%" rmdir /s /q "%WORK%"
  git clone --depth 1 --recurse-submodules --shallow-submodules -b %LOVE_ANDROID_REF% https://github.com/love2d/love-android.git "%WORK%"
  if errorlevel 1 exit /b 1
)

echo == embedding game.love
if not exist "%WORK%\app\src\embed\assets" mkdir "%WORK%\app\src\embed\assets"
copy /y "%LOVE_ZIP%" "%WORK%\app\src\embed\assets\game.love" >nul

set "PROPS=%WORK%\gradle.properties"
if exist "%PROPS%" (
  powershell -NoProfile -Command ^
    "(Get-Content -Raw '%PROPS%') -replace 'app.application_id=.*','app.application_id=%APP_ID%' -replace 'app.version_code=.*','app.version_code=%VERSION_CODE%' -replace 'app.version_name=.*','app.version_name=%VERSION_NAME%' -replace 'app.orientation=.*','app.orientation=landscape' | Set-Content -NoNewline '%PROPS%'"
)

if not defined ANDROID_SDK_ROOT if defined ANDROID_HOME set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
if not defined ANDROID_SDK_ROOT if exist "%LOCALAPPDATA%\Android\Sdk" set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"
if not defined ANDROID_SDK_ROOT (
  echo set ANDROID_SDK_ROOT to your Android SDK
  exit /b 1
)

echo == gradle assembleEmbedNoRecordDebug
pushd "%WORK%"
call gradlew.bat --no-daemon assembleEmbedNoRecordDebug
if errorlevel 1 (popd & exit /b 1)
popd

for /r "%WORK%\app\build\outputs\apk" %%F in (*.apk) do (
  copy /y "%%F" "%APK_OUT%" >nul
  goto :got
)
echo gradle produced no apk
exit /b 1
:got
echo == %APK_OUT%
echo install: adb install -r "%APK_OUT%"
endlocal
