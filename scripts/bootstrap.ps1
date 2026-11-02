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

# 5. Java for Jenkins (21 or newer, current LTS needs 21 or 25)
Step 'Java'
$javaOk = $false
if (Get-Command java -ErrorAction SilentlyContinue) {
    # java -version writes to stderr, cmd keeps PS 5.1 from treating that as an error
    $v = cmd /c "java -version 2>&1" | Select-Object -First 1
    if ($v -match '"(\d+)(\.(\d+))?') {
        $major = [int]$Matches[1]
        if ($major -eq 1) { $major = [int]$Matches[3] }   # old style: 1.8 = Java 8
        $javaOk = $major -ge 21
    }
    if (-not $javaOk) { Write-Host "found $v, need 21+" -ForegroundColor Yellow }
}
# a new install isn't on this shell's PATH yet, so look for the folder too
$jdk21 = Get-ChildItem "$env:ProgramFiles\Eclipse Adoptium" -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($javaOk -or $jdk21) { Write-Host "already there $(if ($jdk21) { "($($jdk21.FullName))" })" }
else { Install-Winget 'EclipseAdoptium.Temurin.21.JDK' }

# 6. ngrok v3 (v2 agents are no longer accepted)
Step 'ngrok'
$ngrokOk = $false
if (Get-Command ngrok -ErrorAction SilentlyContinue) {
    $nv = cmd /c "ngrok version 2>&1" | Select-Object -First 1
    $ngrokOk = $nv -match 'version 3\.'
    if (-not $ngrokOk) { Write-Host "found $nv at $((Get-Command ngrok).Source), need v3" -ForegroundColor Yellow }
}
if ($ngrokOk) { Write-Host 'already there' }
else { Install-Winget 'Ngrok.Ngrok' }
# winget's ngrok is old, free accounts need a recent agent
if (Get-Command ngrok -ErrorAction SilentlyContinue) { cmd /c "ngrok update 2>&1" | Out-Host }
else { Write-Host 'open a new shell and run: ngrok update' -ForegroundColor Yellow }

# 7. Jenkins, installed as a service (LocalSystem = admin, can manage IIS)
Step 'Jenkins'
if (Get-Service Jenkins -ErrorAction SilentlyContinue) { Write-Host 'already there' }
else {
    $msi = Join-Path $env:TEMP 'jenkins.msi'
    # PS 5.1 can't follow the 308 redirect, curl.exe can
    curl.exe -fsSL -o $msi 'https://get.jenkins.io/windows-stable/latest'
    $isMsi = (Test-Path $msi) -and ((Get-Item $msi).Length -gt 10MB)
    if ($LASTEXITCODE -ne 0 -or -not $isMsi) {
        throw 'Jenkins download failed. Download the LTS Windows installer from https://www.jenkins.io/download/, install it (LocalSystem, port 8080, Java = the Temurin 21 folder), then run this script again.'
    }
    # interactive on purpose: you pick the account and the Java 21 folder
    Write-Host 'Jenkins installer opens now:' -ForegroundColor Yellow
    Write-Host '  - service logon: Run service as LocalSystem'
    Write-Host '  - port: 8080'
    Write-Host '  - Java home: the Temurin 21 folder under C:\Program Files\Eclipse Adoptium\'
    Start-Process msiexec.exe -ArgumentList "/i `"$msi`"" -Wait
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
Write-Host '  3. install suggested plugins, you need the GitHub plugin (included in suggested plugins), then follow docs/RUNBOOK.md step 5'
Write-Host '  If the app pool or Jenkins misbehave, reboot once. IIS features sometimes ask for it.'
