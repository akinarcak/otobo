# CareOnCloud ESM Development Runtime

This profile builds the current checkout as a CareOnCloud ESM `careoncloud-web` image and starts MariaDB, Redis, Elasticsearch, the web process and the daemon. It binds HTTP only to localhost by default. A test server may set `CareOnCloud_BIND_ADDRESS` to its private Tailscale address; never use `0.0.0.0` without TLS and an explicit firewall policy.

## Requirements

- Docker Engine or Docker Desktop with Compose v2
- Windows PowerShell 5.1 or PowerShell 7+
- At least 4 GB of free memory for the initial development profile

## First run

```powershell
Set-Location development/careoncloud
Copy-Item .env.example .env
# Replace CareOnCloud_DB_ROOT_PASSWORD in .env with a long random value.
./Invoke-CareOnCloudDev.ps1 Validate
./Invoke-CareOnCloudDev.ps1 Up
./Invoke-CareOnCloudDev.ps1 Setup
./Invoke-CareOnCloudDev.ps1 Smoke
```

Open `http://127.0.0.1:8080/`. `Setup` uses CareOnCloud ESM's development-only `quick_setup.pl`; it must never be used as a production provisioning mechanism.
The helper immediately rotates both development default agent passwords and writes the generated admin login to `.runtime/admin-credentials.env`. This file is ignored by Git and must remain private.

Elasticsearch is optional because its image and memory footprint are substantial. Enable it consistently for `Up`, `Setup`, and later commands when full-text search is required:

```powershell
./Invoke-CareOnCloudDev.ps1 Up -EnableSearch
./Invoke-CareOnCloudDev.ps1 Setup -EnableSearch
```

Search runtime kurulumu sonrasinda `elasticsearch-webservice.yml` dosyasini ve
`Configure-Elasticsearch.pl` scriptini web container'ina kopyalayin. Konfigurator,
yalniz `http://elastic:9200` private servis adresini kabul eder ve var olan invalid
CareOnCloud ESM kaydini idempotent bicimde etkinlestirir. Ardindan su resmi kapilari calistirin:

```text
bin/careoncloud.Console.pl Admin::Config::Update --setting-name Elasticsearch::Active --value 1 --valid 1
bin/careoncloud.Console.pl Maint::Elasticsearch::TestConnection
bin/careoncloud.Console.pl Maint::Elasticsearch::Migration --target t
```

`Accept-ElasticsearchRuntime.pl`, iki gecici tenant dokumaniyla gercek hit/miss
izolasyonunu test eder ve fixture'lari siler. Regresyon testleri Elasticsearch event'i
uretebildigi icin tam testten sonra `Migration --target t` yeniden calistirilarak index
authoritative MariaDB durumundan kurulmalidir.

Prometheus operasyon yuzeyi `CareOnCloudObservability` paketiyle gelir. Scrape tokeninin
yalniz SHA-256 digest'ini SysConfig'e kaydedin; tokeni secret store'dan Prometheus'a
dosya olarak baglayin. Endpoint `/careoncloud/public.pl?Action=PublicCareOnCloudMetrics` ve
standart Bearer auth kullanir. Kurulum ve kabul ayrintilari
`docs/esm/observability/PROMETHEUS.md` dosyasindadir.

## Daily commands

```powershell
./Invoke-CareOnCloudDev.ps1 Build
./Invoke-CareOnCloudDev.ps1 Up
./Invoke-CareOnCloudDev.ps1 Logs
./Invoke-CareOnCloudDev.ps1 Down
```

## Tenant-safe demo catalog

After installing `CareOnCloudCatalog`, `CareOnCloudRequest`, and `CareOnCloudCommitment`, copy `Seed-CareOnCloudDemo.pl` into the web container and
run it as the `careoncloud` user with `CareOnCloud_DEMO_CUSTOMER_PASSWORD` supplied only through
the process environment. The script is idempotent and creates customer login
`demo.customer`, tenant `careoncloud-demo`, a sample laptop approval/fulfillment form, and
an eight-business-hour resolution policy with a 75% warning threshold. Never commit
or print the supplied password. The Perl invocation must include CareOnCloud ESM's bundled
libraries: `perl -I. -IKernel/cpan-lib -ICustom /tmp/Seed-CareOnCloudDemo.pl`.

`Down` preserves database and application volumes. Destructive cleanup is explicit:

```powershell
./Invoke-CareOnCloudDev.ps1 Down -RemoveVolumes
```

Never copy `.env` to a server. Production secrets must come from the deployment platform's secret store. The test-server deployment will use a separate production-oriented Compose overlay after SSH access is verified.
