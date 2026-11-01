# Runbook

Windows machine (or VM), run PowerShell as Administrator where noted.
Ports: Jenkins 8080, Dev 8081, Prod 8082.

## 1. Install

Fast path, one command (PowerShell as Administrator, from the repo root).
It installs only what's missing and runs `setup-iis.ps1` at the end, so you can skip step 4:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
./scripts/bootstrap.ps1
```

Manual path, if you prefer to see each step.
Order matters: **IIS first, Hosting Bundle after**. Otherwise the app returns 500.19 / 502.5
and the fix is Repair on the Hosting Bundle installer.

```powershell
# IIS + management scripts (needed for the WebAdministration module)
Enable-WindowsOptionalFeature -Online -All -FeatureName IIS-WebServerRole, IIS-WebServer, IIS-ManagementConsole, IIS-ManagementScriptingTools
```

Then, in this order (winget ids can differ, check with `winget search`):

```powershell
winget install Microsoft.DotNet.SDK.8
winget install Microsoft.DotNet.HostingBundle.8
winget install Git.Git
winget install EclipseAdoptium.Temurin.17.JDK
winget install ngrok.ngrok
```

Jenkins LTS: Windows installer from jenkins.io, run as a service.
The default LocalSystem account is admin, which is what IIS management needs.
If you picked another account, make it a local administrator.

Restart the Jenkins service after installing everything, so it sees `dotnet` and `git` on PATH.

## 2. Check the app locally

```powershell
dotnet test DemoApp.sln
dotnet run --project DemoApp.Web
```

Open the printed URL, check `/` and `/health`.

## 3. GitHub

1. Create a public repo, push this folder to `main`.
2. `git checkout -b dev` and `git push -u origin dev`.

## 4. IIS

```powershell
./scripts/setup-iis.ps1
```

Check in IIS Manager: sites `DemoDev` (8081) and `DemoProd` (8082).
They stay empty until the first pipeline run.

## 5. Jenkins

1. Open `http://localhost:8080`, install suggested plugins, then **GitHub Integration**.
2. New Item → Pipeline.
3. Pipeline definition: *Pipeline script from SCM* → Git → your repo URL → branch `*/dev` → script path `Jenkinsfile`.
4. Tick *GitHub hook trigger for GITScm polling*.
5. **Build Now** once. Expect: all green, stops at *Approve Prod*, click Promote.
6. Check `http://localhost:8081` and `http://localhost:8082`.

## 6. Webhook

```
ngrok http 8080
```

GitHub repo → Settings → Webhooks → Add:

- Payload URL: `https://<ngrok-id>.ngrok-free.app/github-webhook/` (the trailing slash matters)
- Content type: `application/json`
- Events: just the push event

The ngrok URL changes on every start, so update the webhook before each demo.
Debug deliveries under the webhook's *Recent Deliveries*.

## 7. Demo script (10-15 min)

1. One slide or the README diagram: GitHub → Jenkins → IIS dev → approval → prod.
2. Show both sites running the current version.
3. Edit the `Banner` text in `appsettings.Dev.json` and `appsettings.Production.json`, commit, push to `dev`.
4. Jenkins starts on its own. Walk through the stages while it runs.
5. Dev site shows the new text and version. Pipeline waits at *Approve Prod*. Prod still shows the old one.
6. Click Promote. Prod updates, same version number, same zip.
7. Failure 1, stopped by tests: change the expected status in `EndpointTests.cs` so a test fails. Pipeline stops at Test, nothing deployed.
8. Failure 2, rollback: set `Health.ForceFail` to `true` in `appsettings.Dev.json`. Tests pass, deploy runs, `/health` returns 503, the script rolls back. Pipeline red, Dev still on the previous version.
9. Open `azure-pipelines.yml` and show the mapping table from the README.

Reset after step 8: set `ForceFail` back to `false` and push.

## 8. Next step: monitoring

Not part of this demo. Planned next: expose metrics from the app with prometheus-net,
scrape them with Prometheus, and show the deployed version, request rate and errors in Grafana.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `dotnet` / `git` not found in Jenkins | Restart the Jenkins service after installing. |
| Site returns 500.19 or 502.5 | Hosting Bundle installed before IIS. Repair it, then `iisreset`. |
| Deploy: access denied on app pool or `C:\sites` | Jenkins service account is not admin. |
| `WebAdministration` module not found | IIS management scripts feature missing, or the script ran in `pwsh` instead of Windows PowerShell 5.1. |
| Webhook delivered but no build | Missing trailing `/github-webhook/`, wrong branch specifier, or hook trigger box not ticked. |
| Webhook can't reach Jenkins | ngrok not running, or URL changed since you set it. |
| Port already in use | Another site on 8080-8082. Change ports in `setup-iis.ps1`, `Jenkinsfile`, README. |
| `powershell` step blocked by execution policy | `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine` as admin. |

## Before the demo

- Run the whole flow 3 times from a clean state.
- Record a backup video of one clean run.
- Update the ngrok URL in the webhook.
- Jenkins, IIS and ngrok all running, both sites responding.
