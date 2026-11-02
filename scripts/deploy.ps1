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

# C:\sites\dev\ would otherwise put the backup inside the site folder
$Path = $Path.TrimEnd('\', '/')
$backup = "$Path.bak"

function Stop-Pool($name) {
    if ((Get-WebAppPoolState $name).Value -ne 'Stopped') { Stop-WebAppPool $name }
    # wait for it to really stop, otherwise files stay locked. IIS allows 90s by default
    $i = 0
    while ((Get-WebAppPoolState $name).Value -ne 'Stopped' -and $i -lt 90) { Start-Sleep 1; $i++ }
    if ((Get-WebAppPoolState $name).Value -ne 'Stopped') { throw "App pool $name did not stop within 90 seconds" }
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

# any error from here on goes to the rollback below instead of leaving the site down
$cleared = $false
$healthy = $false
try {
    Stop-Pool $Site

    if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
    Copy-Item $Path $backup -Recurse

    $cleared = $true
    Get-ChildItem $Path -Force | Remove-Item -Recurse -Force
    Expand-Archive -Path $Zip -DestinationPath $Path -Force

    Start-Pool $Site
    $healthy = Test-Health $Port $ExpectedVersion
} catch {
    Write-Host "Deploy error: $($_.Exception.Message)"
}

if ($healthy) {
    Write-Host 'Deploy OK'
    exit 0
}

Write-Host 'Deploy failed, rolling back'
# files only need restoring if the old ones were already removed
if ($cleared) {
    Stop-Pool $Site
    Get-ChildItem $Path -Force | Remove-Item -Recurse -Force
    if (-not (Get-ChildItem $backup -Force)) {
        Write-Host 'No previous version to restore (first deploy), site left empty'
        exit 1
    }
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
