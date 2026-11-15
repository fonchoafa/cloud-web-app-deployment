# smoke-test.ps1 - run from your PC after deploying.
# Usage: .\scripts\smoke-test.ps1 -Url http://<public-ip>
param([Parameter(Mandatory = $true)][string]$Url)

$Url = $Url.TrimEnd('/')
$pass = 0; $fail = 0
function Check($name, $ok) {
  if ($ok) { Write-Host "  [PASS] $name"; $script:pass++ } else { Write-Host "  [FAIL] $name"; $script:fail++ }
}

Write-Host "Testing $Url"

try {
  $health = Invoke-RestMethod "$Url/health" -TimeoutSec 10
  Check "health endpoint returns ok" ($health.status -eq 'ok')
  Check "notes are stored in DynamoDB" ($health.storage.notes -eq 'dynamodb')
  Check "files are stored in S3" ($health.storage.files -eq 's3')
} catch {
  Check "health endpoint reachable" $false
}

try {
  $note = Invoke-RestMethod "$Url/api/notes" -Method Post -ContentType 'application/json' `
    -Body (@{ title = 'smoke test'; body = 'created by smoke-test.ps1' } | ConvertTo-Json)
  Check "can create a note" ([bool]$note.id)

  $list = Invoke-RestMethod "$Url/api/notes"
  Check "note appears in the list" (@($list | Where-Object { $_.id -eq $note.id }).Count -eq 1)

  try {
    Invoke-RestMethod "$Url/api/notes/$($note.id)" -Method Delete | Out-Null
    Check "delete without admin key is refused" $false
  } catch {
    Check "delete without admin key is refused" ($_.Exception.Response.StatusCode.value__ -eq 401)
  }
} catch {
  Check "note API works" $false
}

try {
  $open = Test-NetConnection ($Url -replace '^https?://', '') -Port 3000 -WarningAction SilentlyContinue
  Check "app port 3000 is not exposed" (-not $open.TcpTestSucceeded)
} catch {
  Check "app port 3000 is not exposed" $true
}

Write-Host ""
Write-Host "Result: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
