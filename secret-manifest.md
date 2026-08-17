# Secret manifest

Project: daily-brief

This generated view contains variable names and operating metadata only. Secret values, vault session keys, recovery keys, and access tokens are forbidden.

| Variable | Purpose | Provider | Trust boundary | Owner | Rotation | Consumers | Status |
|---|---|---|---|---|---|---|---|
| `PROJECT_DATA_ROOT` | TODO: classify | Bitwarden Secrets Manager or deployment platform | development | Douglas | on compromise, ownership change, or provider policy |  | needs-classification |
| `VERCEL_ORG_ID` | Owning scope of the deployment | Vercel | deployment | Douglas | on scope change | GitHub Actions or the Vercel CLI | declared |
| `VERCEL_PROJECT_ID` | Which Vercel project this repository deploys to | Vercel | deployment | Douglas | on project recreation | GitHub Actions or the Vercel CLI | declared |
| `VERCEL_TOKEN` | Deployment credential for the reviewed workflow | Vercel | deployment | Douglas | on compromise or member change | GitHub Actions or the Vercel CLI | declared |

Canonical source: `secret-manifest.json`
Refresh: `%USERPROFILE%\.agents\tools\Update-SecretManifest.cmd -Repository <repo>`
