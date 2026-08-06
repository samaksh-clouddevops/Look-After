@echo off
setlocal
if not defined JAVA_HOME set "JAVA_HOME=C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot"
set "GRADLE_HOME=%USERPROFILE%\tools\gradle-8.11.1"
if not exist "%GRADLE_HOME%\bin\gradle.bat" (
  echo Gradle not found at %GRADLE_HOME%
  echo Install Gradle 8.11.1 under %%USERPROFILE%%\tools\gradle-8.11.1
  exit /b 1
)
set "PATH=%JAVA_HOME%\bin;%GRADLE_HOME%\bin;%PATH%"
cd /d "%~dp0"
call "%GRADLE_HOME%\bin\gradle.bat" :lookafter-core:test --no-daemon --console=plain %*
exit /b %ERRORLEVEL%
