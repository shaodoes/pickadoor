@echo off
rem Launches Roblox Studio's built-in MCP server from the newest installed Studio version.
rem (Roblox's own %LOCALAPPDATA%\Roblox\mcp.bat goes stale after Studio updates.)
setlocal
for /f "delims=" %%F in ('powershell -NoProfile -Command "(Get-ChildItem \"$env:LOCALAPPDATA\Roblox\Versions\*\StudioMCP.exe\" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName"') do set "EXE=%%F"
if not defined EXE (
  echo StudioMCP.exe not found. Install or update Roblox Studio. 1>&2
  exit /b 1
)
"%EXE%" %*
