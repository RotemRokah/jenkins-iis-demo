# CI/CD demo: GitHub → Jenkins → IIS

A small ASP.NET Core app with a complete delivery pipeline. A push to `dev` builds,
tests, deploys to a Dev site on IIS, waits for a manual approval, then deploys the
**same artifact** to Production. Failed deploys roll back automatically.

Built with Jenkins because that's the tool I've run in production work. The same flow
is translated to Azure DevOps in [`azure-pipelines.yml`](azure-pipelines.yml).

## Flow

```
 git push dev
      │  GitHub webhook
      ▼
 ┌─────────┐   ┌──────┐   ┌────────────┐   ┌─────────┐
 │  Build  │ → │ Test │ → │ Dep. scan  │ → │ Publish │  demoapp-1.0.N.zip
 └─────────┘   └──────┘   └────────────┘   └────┬────┘
                                                │
                    ┌───────────────────────────┘
                    ▼
            ┌──────────────┐   health check   ┌──────────┐
            │  Deploy Dev  │ ───────────────► │ rollback │ (on failure)
            │  IIS :8081   │                  └──────────┘
            └──────┬───────┘
                   ▼
            ┌──────────────┐
            │ Manual approve│
            └──────┬───────┘
                   ▼
            ┌──────────────┐   health check   ┌──────────┐
            │ Deploy Prod  │ ───────────────► │ rollback │ (on failure)
            │  IIS :8082   │                  └──────────┘
            └──────────────┘
```

| Stage | What happens |
|---|---|
| Build / Test | `dotnet build` + xUnit tests. A failing test stops the pipeline, nothing is deployed. |
| Dependency scan | `dotnet list package --vulnerable`. Marks the build unstable, doesn't block. |
| Publish | Versioned zip (`1.0.<build number>`), archived as a Jenkins artifact. |
| Deploy Dev | `scripts/deploy.ps1`: stop app pool, back up, swap files, start, call `/health`. |
| Approve | Jenkins `input` step with a 30 minute timeout. |
| Deploy Prod | Same zip, same script, no rebuild. |
| Verify | `/health` must return the **expected version**, so a silent failed swap can't pass. |
| Rollback | Health fails → previous files restored, pipeline goes red. |

## Environments

| | Dev | Production |
|---|---|---|
| IIS site / port | `DemoDev` / 8081 | `DemoProd` / 8082 |
| `ASPNETCORE_ENVIRONMENT` | `Dev` | `Production` |
| Config | `appsettings.Dev.json` | `appsettings.Production.json` |

The environment is set per app pool by `scripts/setup-iis.ps1`, so the artifact itself
is identical and only configuration differs.

## Repo layout

```
Jenkinsfile                  pipeline definition
azure-pipelines.yml          same flow for Azure DevOps
scripts/bootstrap.ps1        installs prerequisites, then runs setup-iis
scripts/setup-iis.ps1        one-time IIS setup (sites, pools, env vars)
scripts/deploy.ps1           deploy + health check + rollback
DemoApp.Web/                 the app (/, /health)
DemoApp.Tests/               xUnit tests
monitoring/                  optional Prometheus + Grafana
docs/RUNBOOK.md              setup and demo steps
```

## Jenkins ↔ Azure DevOps

| Jenkins | Azure DevOps |
|---|---|
| `Jenkinsfile` (declarative) | `azure-pipelines.yml` |
| `githubPush()` webhook | `trigger: branches` |
| stages | stages / jobs |
| `archiveArtifacts` | `publish` pipeline artifact |
| `input` approval | approval check on an Environment |
| agent | pool / agent |
| Credentials store | variable groups, Key Vault, service connections |

## What I'd change for production

- Run Jenkins and the deploy with least privilege. The demo uses a service account
  that can manage IIS.
- Secrets in a vault, never in the repo or job config.
- Deploy to several servers behind a load balancer (blue/green or rolling) instead of
  one box with a short outage while the pool is stopped.
- Branch protection and required PR checks on `dev` / `main`.
- Infrastructure as code for the servers, not a setup script.
- Central monitoring and alerting on the deployed version, error rate and latency.

## Running it

See [docs/RUNBOOK.md](docs/RUNBOOK.md).
