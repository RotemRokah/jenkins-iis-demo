#Requires -RunAsAdministrator
# one-time IIS setup: two sites, two app pools, env var per pool
# safe to run again
Import-Module WebAdministration

$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"

$envs = @(
    @{ Name = 'DemoDev';  Port = 8081; Dir = 'C:\sites\dev';  AspEnv = 'Dev' },
    @{ Name = 'DemoProd'; Port = 8082; Dir = 'C:\sites\prod'; AspEnv = 'Production' }
)

foreach ($e in $envs) {
    New-Item -ItemType Directory -Force -Path $e.Dir | Out-Null

    if (-not (Test-Path "IIS:\AppPools\$($e.Name)")) {
        New-WebAppPool -Name $e.Name | Out-Null
    }
    # No Managed Code, ASP.NET Core runs out of process of the CLR pool
    Set-ItemProperty "IIS:\AppPools\$($e.Name)" -Name managedRuntimeVersion -Value ''

    if (-not (Get-Website -Name $e.Name)) {
        New-Website -Name $e.Name -Port $e.Port -PhysicalPath $e.Dir -ApplicationPool $e.Name | Out-Null
    }

    # ASPNETCORE_ENVIRONMENT per pool, picks appsettings.Dev.json / appsettings.Production.json
    & $appcmd set config -section:system.applicationHost/applicationPools "/-[name='$($e.Name)'].environmentVariables.[name='ASPNETCORE_ENVIRONMENT']" /commit:apphost 2>&1 | Out-Null
    & $appcmd set config -section:system.applicationHost/applicationPools "/+[name='$($e.Name)'].environmentVariables.[name='ASPNETCORE_ENVIRONMENT',value='$($e.AspEnv)']" /commit:apphost | Out-Null

    Write-Host "$($e.Name): port $($e.Port), dir $($e.Dir), env $($e.AspEnv)"
}

Write-Host 'IIS ready. Sites stay empty until the first pipeline run.'
