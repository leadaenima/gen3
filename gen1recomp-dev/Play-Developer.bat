@echo off
rem Developer boot: LOVE with --developer (in-game console via backtick).
rem Same project folder as Play-Windows.bat; assumes setup already ran once.
title pokeport - developer
cd /d "%~dp0"
set POKEPORT_DEV=1
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\run.ps1" --developer
if errorlevel 1 (
  echo.
  echo Something went wrong - see the messages above.
  pause
)
