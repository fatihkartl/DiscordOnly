from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
manifest=root/'security/manifest.sha256'
items={}
for line in manifest.read_text('utf-8').splitlines():
    if line.startswith('#') or not line.strip(): continue
    digest, name=line.split('  ', 1)
    assert name not in items and '..' not in name and not name.startswith('/')
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest, name
    items[name]=digest
assert len(items) >= 17
ps=(root/'app/DiscordOnly.ps1').read_text('utf-8-sig')
launcher=(root/'app/launcher.ps1').read_text('utf-8')
assert "Version = '0.3.5'" in ps
assert 'if ($true) { # Explicit consent is mandatory' in ps
assert '$script:AutoConflicts.Enabled=$false' in ps
assert "'SECURITY CHECK'" in ps
assert 'Test-Integrity.ps1' in launcher and 'Integrity verification failed' in launcher
security=(root/'tools/Security-Check.ps1').read_text('utf-8')
assert 'Start-MpScan' in security and 'if ($defenderActive' in security
assert 'DEFENDER SCAN SKIPPED' in security
assert 'Add-MpPreference' not in security and 'Set-MpPreference' not in security
print('Security static and source integrity checks passed. Antivirus scan NOT performed by this test.')
