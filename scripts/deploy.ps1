# deploy a published zip to an IIS site
# backup -> swap -> health check -> rollback if unhealthy
# exit 0 = deployed, exit 1 = failed (rolled back if there was a previous version)
param(
    [Parameter(Mandatory)] [string] $Zip,
    [Parameter(Mandatory)] [string] $Site,
    [Parameter(Mandatory)] [string] $Path,
    [Parameter(Mandatory)] [int]    $Port,
    [string] $ExpectedVersion
)

$ErrorActionPreference = 'Stop'
Import-Module WebAdministration

$backup = "$Path.bak"

function Stop-Pool($name) {
    if ((Get-WebAppPoolState $name).Value -ne 'Stopped') { Stop-WebAppPool $name }
    # wait for it to really stop, otherwise files stay locked
    $i = 0
    while ((Get-WebAppPoolState $name).Value -ne 'Stopped' -and $i -lt 20) { Start-Sleep 1; $i++ }
}

function Start-Pool($name) {
    if ((Get-WebAppPoolState $name).Value -ne 'Started') { Start-WebAppPool $name }
}

function Test-Health($port, $expected) {
    # app needs a few seconds to warm up, so retry
    for ($i = 1; $i -le 10; $i++) {
        try {
            $r = Invoke-WebRequest "http://localhost:$port/health" -UseBasicParsing -TimeoutSec 5
            $body = $r.Content | ConvertFrom-Json
            if ($r.StatusCode -eq 200 -and (-not $expected -or $body.version -eq $expected)) {
                Write-Host "health ok (attempt $i): version $($body.version)"
                return $true
            }
        } catch {
            Write-Host "health attempt $i failed: $($_.Exception.Message)"
        }
        Start-Sleep 2
    }
    return $false
}

Write-Host "Deploying $Zip to $Site ($Path)"

Stop-Pool $Site

if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
Copy-Item $Path $backup -Recurse

Get-ChildItem $Path -Force | Remove-Item -Recurse -Force
Expand-Archive -Path $Zip -DestinationPath $Path -Force

Start-Pool $Site

if (Test-Health $Port $ExpectedVersion) {
    Write-Host 'Deploy OK'
    exit 0
}

Write-Host 'Health check failed, rolling back'
Stop-Pool $Site
Get-ChildItem $Path -Force | Remove-Item -Recurse -Force
if (Get-ChildItem $backup -Force) {
    Copy-Item "$backup\*" $Path -Recurse -Force
}
Start-Pool $Site

# no version check here, just that the old build is serving again
if (Test-Health $Port $null) {
    Write-Host 'Rollback OK, previous version is serving'
} else {
    Write-Host 'Rollback FAILED, site is down. Needs a manual look'
}
exit 1
