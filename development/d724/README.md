# D724 ESM Development Runtime

This profile builds the current checkout as an OTOBO `otobo-web` image and starts MariaDB, Redis, Elasticsearch, the web process and the daemon. It binds HTTP only to localhost by default.

## Requirements

- Docker Engine or Docker Desktop with Compose v2
- Windows PowerShell 5.1 or PowerShell 7+
- At least 4 GB of free memory for the initial development profile

## First run

```powershell
Set-Location development/d724
Copy-Item .env.example .env
# Replace D724_DB_ROOT_PASSWORD in .env with a long random value.
./Invoke-D724Dev.ps1 Validate
./Invoke-D724Dev.ps1 Up
./Invoke-D724Dev.ps1 Setup
./Invoke-D724Dev.ps1 Smoke
```

Open `http://127.0.0.1:8080/`. `Setup` uses OTOBO's development-only `quick_setup.pl`; it must never be used as a production provisioning mechanism.

## Daily commands

```powershell
./Invoke-D724Dev.ps1 Build
./Invoke-D724Dev.ps1 Up
./Invoke-D724Dev.ps1 Logs
./Invoke-D724Dev.ps1 Down
```

`Down` preserves database and application volumes. Destructive cleanup is explicit:

```powershell
./Invoke-D724Dev.ps1 Down -RemoveVolumes
```

Never copy `.env` to a server. Production secrets must come from the deployment platform's secret store. The test-server deployment will use a separate production-oriented Compose overlay after SSH access is verified.
