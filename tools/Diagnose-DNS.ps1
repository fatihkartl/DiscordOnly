#requires -version 5.1
# Read-only DNS check - never changes system configuration.
$ErrorActionPreference='Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host 'DiscordOnly - Read-only DNS diagnostics' -ForegroundColor Cyan
Write-Host ('Time: {0}' -f (Get-Date -Format s))
Write-Host ''
Write-Host 'IPv4 DNS servers configured per adapter:'
try {
  Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses.Count -gt 0 } |
    ForEach-Object { Write-Host ('  {0}: {1}' -f $_.InterfaceAlias, ($_.ServerAddresses -join ', ')) }
} catch { Write-Host ('Could not read adapter DNS: ' + $_.Exception.Message) }
Write-Host ''
$blocked=$false
foreach($domain in @('discord.com','updates.discord.com','discord.gg')) {
  try {
    $ips = @([Net.Dns]::GetHostAddresses($domain) | ForEach-Object { $_.IPAddressToString })
    Write-Host ('System DNS {0}: {1}' -f $domain, ($ips -join ', '))
    if ($ips -contains '195.175.254.2') {
      Write-Host '  => KNOWN TURKISH DNS BLOCK RESPONSE' -ForegroundColor Red
      $blocked=$true
    }
  } catch { Write-Host ('DNS failure for {0}: {1}' -f $domain,$_.Exception.Message) }
}
Write-Host ''
try {
  $answer=Invoke-RestMethod -Uri 'https://cloudflare-dns.com/dns-query?name=discord.com&type=A' -Headers @{Accept='application/dns-json'} -TimeoutSec 6 -ErrorAction Stop
  $ip = @($answer.Answer | Where-Object {$_.type -eq 1} | ForEach-Object { $_.data }) -join ', '
  Write-Host ('Independent encrypted DNS answer: {0}' -f $ip)
} catch { Write-Host ('Could not query encrypted DNS: ' + $_.Exception.Message) }
Write-Host ''
if($blocked) {
  Write-Host 'ACTION: DNS block response detected. Correct DNS first; DPI alone cannot fix a false IP.' -ForegroundColor Yellow
  Write-Host 'On Windows 11 prefer 1.1.1.1 + 1.0.0.1 with DNS over HTTPS enabled.'
  Write-Host 'DNS server changes affect all apps DNS lookups, not gameplay packet routing.'
} else {
  Write-Host 'No known DNS block response found. TLS/DPI may still be blocked.' -ForegroundColor Green
}
Write-Host 'This tool did not modify any DNS settings.'
