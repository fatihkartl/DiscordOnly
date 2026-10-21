#requires -version 5.1
# Legacy shortcut: run the verified complete recovery, not an unsafe partial cleanup.
& (Join-Path $PSScriptRoot 'Repair-All.ps1')
if (!$?) { exit 1 }
