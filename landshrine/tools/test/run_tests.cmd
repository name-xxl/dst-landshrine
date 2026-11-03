@echo off
rem Offline unit test entry (double-click or run from command line).
rem Uses lua.exe from PATH; if yours is elsewhere, set LUA_EXE first:
rem   set LUA_EXE=C:\path\to\lua.exe
setlocal
if defined LUA_EXE (set "LUA=%LUA_EXE%") else (set "LUA=lua.exe")
"%LUA%" "%~dp0run_tests.lua" %*
