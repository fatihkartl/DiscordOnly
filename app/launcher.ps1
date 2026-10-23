# DiscordOnly startup wrapper: always preserves a usable error report.
# PowerShell 5.1 / Windows 10,11.
$ErrorActionPreference = 'Stop'
$main = Join-Path $PSScriptRoot 'DiscordOnly.ps1'
$stateRoot = Join-Path $env:LOCALAPPDATA 'DiscordOnly'
$errorLog = Join-Path $stateRoot 'startup-error.log'

function Report-StartupFailure($failure) {
    $detail = $failure | Out-String
    $stack = try { [string]$failure.ScriptStackTrace } catch { '' }
    $message = ('[{0}] DiscordOnly startup failed' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) + [Environment]::NewLine + $detail + [Environment]::NewLine + $stack
    try {
        [void][System.IO.Directory]::CreateDirectory($stateRoot)
        Add-Content -LiteralPath $errorLog -Value $message -Encoding UTF8
    } catch { }
    Write-Host $message -ForegroundColor Red
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $short = [string]$failure.Exception.Message
        if ($short.Length -gt 950) { $short = $short.Substring(0,950) }
        [void][System.Windows.Forms.MessageBox]::Show(
            "DiscordOnly could not start.`r`n`r`n$short`r`n`r`nDetailed report:`r`n$errorLog",
            'DiscordOnly - Startup error', 'OK', 'Error')
    } catch { }
}

try {
    if (!(Test-Path -LiteralPath $main)) { throw "Missing application file: $main. Extract the entire ZIP before launching Start.cmd." }
    # Fail closed if a source file has been changed since this release was packaged.
    # This is a local checksum check, NOT an antivirus verdict or signed attestation.
    $root = Split-Path -Parent $PSScriptRoot
    $auditScript = Join-Path $root 'tools\Test-Integrity.ps1'
    $manifest = Join-Path $root 'security\manifest.sha256'
    if (!(Test-Path -LiteralPath $auditScript) -or !(Test-Path -LiteralPath $manifest)) {
        throw 'Security integrity files missing. Download and extract the full official project archive again. Do not bypass antivirus alerts.'
    }
    $integrityOk = & $auditScript -Root $root -ManifestFile $manifest -Quiet
    if ($integrityOk -ne $true) {
        throw 'Integrity verification failed. Application startup blocked. Run Security-Check.cmd and reinstall from a trusted source.'
    }
    # Capture syntax errors in GUI files before attempting elevation.
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($main, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $details = ($parseErrors | ForEach-Object { 'Line {0}: {1}' -f $_.Extent.StartLineNumber, $_.Message }) -join '; '
        throw "PowerShell script syntax error: $details"
    }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    $admin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($admin) {
        & $main
    } else {
        # Elevate the *wrapper*, not the GUI script, so exceptions are shown/logged.
        $exe = Join-Path $PSHOME 'powershell.exe'
        Start-Process -FilePath $exe -Verb RunAs -WindowStyle Hidden -WorkingDirectory (Split-Path -Parent $main) -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $PSCommandPath + '"') -ErrorAction Stop | Out-Null
        # This non-admin process exits normally while elevated UI remains open.
    }
} catch {
    Report-StartupFailure $_
    exit 1
}
