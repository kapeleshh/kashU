@echo off
echo ========================================
echo  kashU - Build Debug APK
echo ========================================
echo.

REM Set paths
set FLUTTER_PATH=C:\Program Files\Android\flutter\bin\flutter.bat
set PROJECT_PATH=%~dp0

REM Check if Flutter exists at default path
if not exist "%FLUTTER_PATH%" (
    echo Flutter not found at %FLUTTER_PATH%
    echo Trying to find flutter in PATH...
    where flutter >nul 2>&1
    if %errorlevel% neq 0 (
        echo ERROR: Flutter not found. Please install Flutter or update FLUTTER_PATH in this script.
        pause
        exit /b 1
    )
    set FLUTTER_PATH=flutter
)

echo Building debug APK...
echo Project: %PROJECT_PATH%
echo.

cd /d "%PROJECT_PATH%"
"%FLUTTER_PATH%" build apk --debug

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo  SUCCESS! APK built successfully.
    echo ========================================
    echo.
    echo APK location:
    echo %PROJECT_PATH%build\app\outputs\flutter-apk\app-debug.apk
    echo.
    echo Opening APK folder...
    explorer "%PROJECT_PATH%build\app\outputs\flutter-apk\"
) else (
    echo.
    echo ========================================
    echo  BUILD FAILED
    echo ========================================
    echo Please check the error messages above.
)

pause
