#Requires -RunAsAdministrator
# one-shot machine prep for the demo
# installs only what's missing, in the right order, then runs setup-iis.ps1
# safe to run again
$ErrorActionPreference = 'Stop'

function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

function Install-Winget($id) {
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {   # -1978335189 = already installed
        throw "winget failed for $id (exit $LASTEXITCODE)"
    }
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Update "App Installer" from the Microsoft Store and run again.'
}

# 1. IIS first. Hosting Bundle must come after it
Step 'IIS features'
Enable-WindowsOptionalFeature -Online -All -NoRestart -FeatureName `
    IIS-WebServerRole, IIS-WebServer, IIS-ManagementConsole, IIS-ManagementScriptingTools | Out-Null

# 2. .NET SDK 8
Step '.NET SDK 8'
if (dotnet --list-sdks 2>$null | Select-String '^8\.') { Write-Host 'already there' }
else { Install-Winget 'Microsoft.DotNet.SDK.8' }

# 3. Hosting Bundle (the ASP.NET Core module for IIS)
Step '.NET Hosting Bundle 8'
if (Test-Path "$env:ProgramFiles\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll") { Write-Host 'already there' }
else { Install-Winget 'Microsoft.DotNet.HostingBundle.8' }

# 4. Git
Step 'Git'
if (Get-Command git -ErrorAction SilentlyContinue) { Write-Host 'already there' }
else { Install-Winget 'Git.Git' }

# 5. Java for Jenkins (17 or newer)
Step 'Java'
$javaOk = $false
if (Get-Command java -ErrorAction SilentlyContinue) {
    $v = (& java -version 2>&1 | Select-Object -First 1).ToString()
    if ($v -match '"(\d+)') { $javaOk = [int]$Matches[1] -ge 17 }
}
if ($javaOk) { Write-Host 'already there' }
else { Install-Winget 'EclipseAdoptium.Temurin.17.JDK' }

# 6. ngrok
Step 'ngrok'
if (Get-Command ngrok -ErrorAction SilentlyContinue) { Write-Host 'already there' }
else { Install-Winget 'ngrok.ngrok' }

# 7. Jenkins, installed as a service (LocalSystem = admin, can manage IIS)
Step 'Jenkins'
if (Get-Service Jenkins -ErrorAction SilentlyContinue) { Write-Host 'already there' }
else {
    $msi = Join-Path $env:TEMP 'jenkins.msi'
    Invoke-WebRequest 'https://get.jenkins.io/windows-stable/latest' -OutFile $msi
    Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait
}

# 8. IIS sites
Step 'IIS sites'
iisreset | Out-Null
& "$PSScriptRoot\setup-iis.ps1"

# restart so the Jenkins service sees the new PATH (dotnet, git)
if (Get-Service Jenkins -ErrorAction SilentlyContinue) { Restart-Service Jenkins }

Write-Host "`nDone. Next:" -ForegroundColor Green
Write-Host '  1. open http://localhost:8080 (give Jenkins a minute to start)'
$pw = 'C:\ProgramData\Jenkins\.jenkins\secrets\initialAdminPassword'
if (Test-Path $pw) { Write-Host "  2. unlock with: $(Get-Content $pw)" }
Write-Host '  3. install suggested plugins + GitHub Integration, then follow docs/RUNBOOK.md step 5'
Write-Host '  If the app pool or Jenkins misbehave, reboot once. IIS features sometimes ask for it.'
