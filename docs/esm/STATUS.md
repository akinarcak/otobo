# CareOnCloud ESM Durum Kaydı

## 2026-08-02 — P0.5 lisans metadata tutarlılığı

- `VERIFIED_BY_CURRENT_TEST`: CareOnCloud kaynak ve paket politikası `GPL-3.0-only` olarak tekleştirildi. D724 paket kaynak başlıkları, Foundation tanılama manifesti, API kontratı ve ticari politika zaten bu tanımla uyumluydu; root README ve NOTICE'daki eski `GPL-3.0-or-later` ifadesi `GPL-3.0-only` olarak düzeltildi. SOPM'lerin tam GPL v3 metadatası (`GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007`) aynı lisans tercihini taşır.
- `Test-Foundation.ps1` artık README, NOTICE ve GPL-COMMERCIAL politikasında açık `GPL-3.0-only` tanımını ve çelişen `GPL-3.0-or-later` ifadesinin yokluğunu; tüm D724 SOPM manifestlerinde de kanonik GPL v3 metadatasını zorunlu kılar. Upstream telif ve GPL bildirimleri korunur. Bu bir hukuki görüş değil, depodaki metadata sözleşmesidir.

## 2026-08-02 — P0.2 API transaction ownership correction

- `D724API` transaction paths now capture ownership before calling `BeginWork()` and commit or roll back only transactions they opened themselves. This covers client create, token issue/revoke, secret rotation, client revoke, and retention cleanup.
- `APIAuth.t` now contains an outer-transaction regression: a nested client creation must leave the caller transaction open, and the caller rollback must remove both the client and its audit mutation.
- Evidence: `VERIFIED_BY_CURRENT_TEST`. On 2026-08-02, `APIAuth.t` passed with 59 tests in an isolated transient container using the CareOnCloud candidate app volume and the test-server MariaDB. The active `d724-esm` web and daemon containers were not changed. Test artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/api-auth-0.7.2-test.log`. Rollback: restore `packages/D724API` from the adjacent timestamped backup and restore the candidate-volume files from `/opt/careoncloud/.codex-backup-p0-api-20260802`; neither rollback affects the active old OTOBO volumes.
- `RISK` / candidate recovery: the first isolated `APIStatus.t` run found `bin/psgi-bin/careoncloud.psgi` absent from the candidate app volume. Copying the canonical core file to that unused candidate volume made `APIStatus.t` pass 25 tests; artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/api-status-0.7.2-rerun.log`. `bin/docker/entrypoint.sh` now restores this file only when absent and fails closed if the image source is absent; Bash syntax was checked on the test server. A fresh candidate web start using a newly built image is still required before cutover.

## 2026-08-02 — P0.2 ticket audit coverage inventory

- `VERIFIED_IN_CODE`: [Ticket audit coverage inventory](security/TICKET-AUDIT-COVERAGE.md) records all direct core ticket mutators identified by the current P0 inventory. No claim of full TicketAudit coverage is made; indirect write routes remain separate.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.2` adds transaction-atomic `TicketTypeSet` coverage. Candidate MariaDB regression `TicketAudit.t` passed 64 tests, including audit-disabled type rollback, successful scope-version advancement, and normalized `ticket.type.updated` evidence. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/ticket-audit-0.8.2-test.log`.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.3` adds transaction-atomic `TicketServiceSet` coverage. Candidate MariaDB regression `TicketAudit.t` passed 71 tests, including audit-disabled service rollback, successful scope-version advancement, and normalized `ticket.service.updated` evidence. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/ticket-audit-0.8.3-test.log`. The test service fixture is removed by its exact database ID because the core exposes no `ServiceDelete` API.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.4` adds `TicketDelete` and same-tenant `TicketMerge` coverage. Candidate MariaDB regression `TicketAudit.t` passed 95 tests, including audit-disabled delete/merge rollback, cross-tenant merge rejection, two-scope merge version advancement, normalized merge/delete evidence, and chain verification. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/ticket-audit-0.8.4-test.log`. `RISK`: core delete dispatches index/storage hooks outside the MariaDB audit contract; the rollback case produced an Elasticsearch version-conflict log, so cross-system atomicity is not claimed.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.5` adds transaction-aware `TicketSLASet` and `TicketPendingTimeSet` coverage. Candidate MariaDB regression `TicketAudit.t` passed 108 tests, including audit-disabled SLA/pending-time rollback, successful scope-version advancement, normalized `ticket.sla.updated` / `ticket.pending_time.updated` evidence, and fixture foreign-key cleanup. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/ticket-audit-0.8.5-test.log`.

## 2026-08-02 — P0.2 indirect ticket write-route inventory

- `VERIFIED_IN_CODE`: [Indirect ticket write-route inventory](security/TICKET-AUDIT-INDIRECT-ROUTES.md) confirms that Generic Interface TicketCreate/TicketUpdate and several event modules call the standard wrapped ticket methods. Generic Interface `TicketUpdate` additionally has request-level transaction coverage; scheduler and daemon routes remain separate.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.6` adds transaction-aware Chat `ArticleCreate` coverage. Candidate MariaDB regression `TicketAudit.t` passed 115 tests, including audit-disabled chat article rollback, successful scope-version advancement, and normalized `ticket.chat_article.created` evidence. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/ticket-audit-0.8.6-test.log`.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.7` wraps Chat `ArticleUpdate` and `ArticleDelete` in the same scope-lock, transaction, and normalized-audit contract. Candidate MariaDB regression passed `TicketAudit.t` (124) and `TicketAuditStatus.t` (11), including audit-disabled update/delete rollback, successful scope-version advancement, and the complete chat lifecycle evidence. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/ticket-audit-0.8.7-rerun.log`. `RISK`: Chat update triggers core search indexing, which remains outside the MariaDB transaction boundary.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.9` wraps Generic Interface `TicketUpdate::Run` in a request-level transaction and gives nested ticket mutations savepoints. Candidate MariaDB regression passed `TicketAudit.t` (128) and `TicketAuditStatus.t` (11), including a later request failure that rolls an earlier successful title mutation, scope version, audit record, and cache state back. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/ticket-audit-0.8.9-gi-atomicity.log`.
- `VERIFIED_BY_CURRENT_TEST`: an isolated clean MariaDB/Redis/web candidate installed the Foundation/TenantGuard/TenantDirectory/Audit/TicketAudit chain, rotated the fresh `admin` password to a random process-scoped value, and accepted a real authenticated two-field REST `TicketUpdate` through `/careoncloud/nph-genericinterface.pl`. The persisted title and priority were re-read after cache invalidation, scope version advanced from 1 to 3, both normalized audit actions were present, and the tenant audit chain verified. The temporary provider and the exact Compose project, network, and volumes were removed; active `d724-esm` services remained healthy. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/gi-http-acceptance.log`. The committed clean-lifecycle CI gate now retains the same contract; a GitHub Actions run is still unverified.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.12` runs the core `Maint::Ticket::PendingCheck` command once per active tenant with a TenantGuard-authorized automation context. It records state changes through a scope-lock/audit transaction after the core pending check, so the scheduler worker's forced package reload cannot bypass the tenant scope or immutable audit update. A fresh isolated Compose project ran the actual `SchedulerTaskWorker` fork and Cron handler: the pending ticket transitioned to `closed successful`, scope advanced from 3 to 4, the normalized state audit event was present, and the tenant chain verified. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/scheduler-pending-check-acceptance.log`. The temporary project and volumes were removed; active `d724-esm` services were not changed. This accepts only the core pending-check scheduler route, not GenericAgent, other daemon jobs, direct database writes, or external side effects.

## 2026-08-02 — P0.4 candidate package-install gate

- `VERIFIED_BY_CURRENT_TEST`: `Test-CareOnCloudBrand.ps1` passed against the current checkout (16 required CareOnCloud paths, 15 forbidden legacy paths, and all 18 package manifests). The D724 foundation workflow now runs this source-contract check. This is a static source guard, not proof that a running candidate has no upstream brand residue in headers, cookies, logs, emails, or rendered pages.
- `VERIFIED_BY_CURRENT_TEST`: a fresh isolated runtime candidate served `/careoncloud/index.pl` with `X-CareOnCloud-Login`, `CareOnCloudBrowserHasCookie`, and a `CareOnCloud ESM` product header. Its visible login response contained no `OTOBO` or `OTRS` token after preserving the upstream copyright comments required in the rendered source. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/runtime-brand-acceptance.log`. The temporary Compose project and volumes were removed; active `d724-esm` services were not changed. This acceptance covers the anonymous login response only, not authenticated portal/agent/admin screens, email, logs, or external integrations.
- `VERIFIED_BY_CURRENT_TEST`: the D724 GitHub Actions workflow now triggers for every `packages/D724*/**` change, as well as framework and container-entrypoint changes that affect package deployment. `Test-Foundation.ps1` validates all 18 current D724 package manifests, tracked file-list entries, GPL metadata, XML well-formedness, and the framework-required `otobo_config` root/init values. Local no-Docker validation passed on 2026-08-02; this is a static CI gate, not evidence that GitHub Actions is enabled for the fork or that every package lifecycle runs in CI.
- `VERIFIED_BY_CURRENT_TEST`: the same local CI gate scans D724 packages, development release files, ESM documentation, and GitHub configuration for committed private-key blocks, AWS access-key identifiers, and GitHub token identifiers. It passed on 2026-08-02. This is a narrow high-confidence secret-material guard, not a replacement for repository secret scanning or dependency/SBOM tooling.
- `VERIFIED_BY_CURRENT_TEST`: the candidate console supports `Dev::Package::Build` and `Admin::Package::Install` (not `Admin::Package::Build`). A transient container built the D724Problem OPM, installed 0.2.0, then upgraded it to 0.2.2 on the unused candidate app volume and MariaDB. The package manager applied the `d724_problem` schema and loaded `D724::Problem::Enabled = 1`.
- `VERIFIED_BY_CURRENT_TEST`: D724Problem 0.2.2 uses savepoints when called inside a caller-owned transaction, so an audit write failure rolls back only the Problem mutation. Candidate regressions passed: `Problem.t` 20, `ProblemFrontend.t` 6, and `ProblemStatus.t` 2. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/problem-package-0.2.2-upgrade-tests.log`. Active `d724-esm` web and daemon containers were not changed.
- `VERIFIED_BY_CURRENT_TEST`: candidate lifecycle acceptance uninstalled D724Problem 0.2.2, observed `DROP TABLE d724_problem` and the removed SysConfig setting, then rebuilt, reinstalled, and reran `Problem.t` (20), `ProblemFrontend.t` (6), and `ProblemStatus.t` (2) successfully. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/problem-package-0.2.2-uninstall-reinstall.log`. `RISK`: the candidate volume contains historical manually-copied `.save` preimages using the old XML root, which causes a SysConfig warning during uninstall recovery; the subsequent clean OPM installation and settings load succeed. A fresh candidate volume is required for clean lifecycle acceptance before cutover.
- `RISK` / fresh-volume attempt: on 2026-08-02 a separately named unused app volume was seeded from `d724/esm:dev` and given only the existing candidate DB connection configuration. Reinstalling the minimal Foundation/TenantGuard/TenantDirectory/Audit/Problem chain exposed that the current image still contains the old `careoncloud_config` framework parser and lacks the current D724TicketAudit file expected by persisted SysConfig. The clean-volume lifecycle is therefore **not accepted**. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/problem-clean-volume-lifecycle.log`. Required remediation: rebuild `d724/esm:dev` from the committed source, then repeat clean-volume install/upgrade/uninstall/reinstall before any cutover.
- `VERIFIED_BY_CURRENT_TEST`: `d724/esm:dev` was rebuilt on the test server from the synchronized committed framework sources without restarting active web or daemon containers. A direct image inspection confirms the new `/opt/careoncloud_install/careoncloud_next/Kernel/System/SysConfig.pm` parses `otobo_config`. The clean-volume lifecycle must still be repeated from a newly seeded volume; the historical clean volume predates this rebuilt image.
- `VERIFIED_BY_CURRENT_TEST`: a second separately named unused volume was seeded from the rebuilt image. It contains the `otobo_config` parser and no preinstalled D724Problem files, proving a clean application-volume bootstrap. This is not yet full lifecycle acceptance because the candidate DB's D724 dependency records require the dependency package chain to be installed into this new volume before D724Problem can be exercised.
- `RISK` / clean-volume lifecycle: after the Foundation/TenantGuard/TenantDirectory/Audit/TicketAudit/Problem chain was reinstalled into that clean volume, D724Problem uninstall removed its files and issued `DROP TABLE d724_problem`, but `Admin::Config::Read` still returned `D724::Problem::Enabled = 1`. Clean-volume uninstall/reinstall acceptance is therefore still failed: SysConfig cleanup must be corrected before reinstall can be claimed safe. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/problem-clean-v2-lifecycle-rerun.log`.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.10` changes its `Ticket::CustomModule` value to the framework-compatible `String` type. A candidate `Admin::Package::Upgrade` (rather than `Reinstall`, which intentionally leaves the repository version unchanged) recorded `0.8.10` and reported its package deployment as `OK`. This removes the prior TicketAudit XML setting validation error.
- `RISK` / clean-volume lifecycle root cause: the clean application volume reuses the candidate MariaDB package repository, which still records many D724 packages whose files are absent from that volume. `Admin::Package::List --show-deployment-info` reports those packages as `Not OK`; PackageManager therefore deliberately disables SysConfig cleanup to avoid deleting settings for temporarily absent packages. An explicit `Maint::Config::Rebuild --cleanup` removes the stale `D724::Problem::Enabled` setting, proving the setting is otherwise removable. This is not lifecycle acceptance: a dedicated clean database (or a complete, version-matched package set) is required before package uninstall/reinstall can be accepted.
- `VERIFIED_BY_CURRENT_TEST`: a separately named temporary Compose project, with new MariaDB/Redis/application volumes, was initialized using `quick_setup.pl`; its daemon was stopped before tests. Only the matching `D724Foundation`, `D724TenantGuard`, `D724TenantDirectory`, `D724Audit`, and `D724Problem` OPMs were installed. Every installed package reported `Pck. Status: OK`. D724Problem passed 28 tests before and after uninstall/reinstall; uninstall removed the table and made `D724::Problem::Enabled` invalid, then reinstall restored the package. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/problem-clean-db-lifecycle.log`. The temporary containers, network, and only their named volumes were removed after evidence capture; active `d724-esm` containers were not changed.
- `VERIFIED_IN_CODE` / candidate compatibility: internal SysConfig XML schema names were restored from `careoncloud_config` to the framework-required `otobo_config`; CareOnCloud remains the product-facing name. This prevents package configuration deployment from silently skipping settings.

- `RISK`: Candidate MariaDB runtime acceptance for `D724Problem 0.2.0` was attempted with all three package tests. It failed because `d724_problem` is absent from the candidate database; copying source files alone does not apply the manifest `DatabaseInstall` schema. The candidate console has no `Admin::Package::Build` command, so a reproducible OPM build/install/upgrade pipeline is required before this package can be accepted. Test artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/problem-candidate.log`. The failed test left zero `problem-%` tenant fixtures.

Son dogrulama: `2026-07-25`

## Calisan ve kanitlanmis

- OTOBO `rel-11_1` tabanli GitHub forku ve `codex/esm-foundation` gelistirme dali.
- Kaynak koddan uretilen `d724/esm:dev` container image'i.
- MariaDB, Redis, OTOBO web ve daemon servislerinden olusan izole Compose profili.
- Digest-pinned Elasticsearch 8.19.3 servisi; yalniz Docker ic aginda, cluster `green`, OTOBO resmi connection testi basarili.
- Ozel test aginda HTTP health ve agent giris sayfasi: HTTP 200.
- OTOBO konsolundan SysConfig rebuild ve daemon status kontrolleri.
- GPL-3.0 `D724Foundation 0.2.1` uyumluluk adlı CareOnCloud temel OPM paketi:
  - urun ve edition SysConfig ayarlari,
  - telemetry icin opt-in varsayilani,
  - `Admin::D724::FoundationStatus --json` tanilama komutu,
  - paket deployment kontrolu `OK`,
  - CareOnCloud ESM ürün adı, resmi Careon logo varlıkları ve `Hizmet Bulutta, Kontrol Sizde.` sloganı,
  - iki test dosyası dahil birleşik regresyonda sonuç `PASS`.
- GPL-3.0 `D724TenantGuard 0.9.0` / policy contract `1.7.0` OPM paketi:
  - varsayilan-reddet action/role matrisi,
  - exact ve buyuk/kucuk harf duyarli tenant siniri,
  - query'ler icin fail-closed `ScopeGet`,
  - varsayilan kapali global platform admin gecisi,
  - karar neden kodlari ve JSON tanilama komutu,
  - tenant-bazli role bindings ile multi-tenant privilege bleed engeli,
  - aktif tenant icin tek-tenant `automation:<job>` subject'i ve default-deny `automation.execute` karari,
  - `auditor`, `service_owner` ve `tenant_admin` icin tenant-bound `report.read`/`report.export`; agent/requester default-deny,
  - kalici-backend kullanan `D724::TenantCache`: her operasyonda aktif tenant + merkezi policy, hash'li tenant namespace'i, TTL ust siniri ve tenant-izole delete/cleanup,
  - `Admin::D724::TenantCacheStatus --json` operasyon kapisi,
  - tenant-bound `search.read` action'i ve tum bilinen tenant rollerinde acik grant,
  - beş test dosyası, 168 test, sonuç `PASS`,
  - ayni tenant karari `ALLOW_ROLE_ACTION`, capraz tenant karari `DENY_CROSS_TENANT`.
- GPL-3.0 `D724SCIM 0.1.5` OPM paketi:
  - mevcut tenant-bound bcrypt API client ve digest-only bearer token altyapisini kullanan `scim.provision` yetkisi,
  - ajan ve musteri hesabi create/get/list/replace/deprovision/reactivate yasam dongusu,
  - immutable `externalId`/`userName`, weak ETag ve zorunlu `If-Match` optimistic concurrency,
  - SCIM grup uyeliginden tenant rol uzlastirmasi; deprovision'da tum tenant rollerini revoke ve reactivation'da restore,
  - baska aktif tenant uyeligi olan ajanin global hesabini kapatmama,
  - tenant ile birlikte baglanan tum user/group/member sorgulari ve cross-tenant `403`, bilinmeyen kaynak `404`,
  - integration actor ile transaction-atomic audit zinciri,
  - canonical `/careoncloud/scim/v2` Users/Groups/discovery REST tasiyicisi, bounded `eq` filtre ve SCIM hata medyasi,
  - gercek MariaDB kabulunde 29/29 test `PASS`; public HTTPS kimliksiz istek `401 application/scim+json`.
- GPL-3.0 `D724TenantDirectory 0.2.1` OPM paketi:
  - kalici tenant ve agent-role membership tablolari,
  - directory-derived agent policy context'i,
  - one-time confirmed bootstrap ve tenant/member mutation audit olaylari,
  - membership optimistic version'i ve idempotent grant/revoke replay'i,
  - tenant-row `FOR UPDATE` kilidi ile last-admin revoke yarisi ve tenant self-deactivation lockout engelleri,
  - domain mutation ile audit head/event append'inin tek transaction'da commit/rollback garantisi,
  - audit kapali grant/revoke hata enjeksiyonunda satir ve version rollback'i; ayni girdinin retry basarisi,
  - dort test dosyasi, 57 test, sonuc `PASS`.
- GPL-3.0 `D724Catalog 0.6.1` OPM paketi:
  - Service, ServiceOffering ve CatalogItem MariaDB semasi,
  - tenant-guarded create/get/list/update repository API'si,
  - tenant icinde benzersiz key, lifecycle ve optimistic version kontrolu,
  - versioned ve whitelist-validasyonlu dinamik form semasi,
  - authenticated customer session'dan tenant tureten katalog portal modulu,
  - yalnizca tam aktif hierarchy listeleme ve parent availability kontrolu,
  - HTML escape ve gercek OTOBO template render testleri,
  - tenant directory context'inden beslenen agent yonetim ekrani,
  - Service/Offering/Item lifecycle ve JSON form semasi yonetimi,
  - CSRF challenge token ve optimistic update formlari,
  - service/offering/item/schema create-update icin normalize audit olaylari ve mutation+audit transaction atomikligi,
  - yedi test dosyası, 81 paket testi, sonuç `PASS`,
  - offering→service, item→offering ve schema→item için tenant ID ile parent ID'yi birlikte zorlayan üç gerçek composite MariaDB foreign key,
  - doğrudan SQL çapraz-tenant parent bağlama negatif testi ve status health kapısı,
  - authenticated customer HTTP katalog ve dinamik form smoke testleri.
- GPL-3.0 `D724Request 0.4.8` uyumluluk adlı request OPM paketi:
  - sunucu-tarafli dinamik cevap validasyonu ve workflow snapshot'i,
  - tenant/requester kapsamli idempotent form submission,
  - tenant-role onayi ve optimistic-lock durum gecisleri,
  - fulfillment gorevleri, basarisizlik ve otomatik fulfilled sonucu,
  - musteri makbuzu ve agent onay/fulfillment workbench'i,
  - request create, approval, first-response ve task/fulfillment yazimlarini audit append ile ayni DB transaction'inda commit/rollback,
  - oturumlu HTTP submit sonrasi `REQ-*` makbuzu ve agent gorunurluk testi.
- GPL-3.0 `D724Audit 0.2.0` OPM paketi:
  - tenant-bazli monoton sequence ve SHA-256 previous/event hash zinciri,
  - normalize actor/action/object/correlation/state/outcome/details kontrati,
  - source IP'nin salt'li SHA-256 pseudonym'i ve clear-text export yasagi,
  - `audit.read` policy kontrolu, tenant/object filtresi, cursor pagination ve NDJSON export,
  - tenant + `dedupe_key` benzersizligi ile tekrar teslimde ayni olay sonucunun donmesi,
  - request, katalog ve tenant-directory mutation adapter'lari,
  - temel katman olarak tenant-directory paketine statik bagimlilik olmadan subject veya opsiyonel directory-derived authorization,
  - zincir, head, sequence gap ve event hash dogrulayan `Verify` API'si,
  - iki test dosyasi, 29 test, sonuc `PASS`.
- `D724Problem 0.2.0` backend and agent RCA workbench is present in the current checkout. Problem state transitions use tenant-scoped row locking together with optimistic versions and transactional audit; creation has an audit-failure rollback regression case. Runtime acceptance is pending because this workspace currently has no Docker or Perl executable.
- GPL-3.0 `D724TicketAudit 0.8.1` OPM paketi:
  - resmi `Ticket::CustomModule` extension noktasi ile cekirdek dosya fork'u olmadan repository wrapping,
  - her OTOBO ticket icin immutable `d724_ticket_scope` tenant binding ve monoton mutation version'i,
  - ticket create ile title/queue/customer/lock/state/owner/responsible/priority mutasyonlarinda domain+scope+audit tek transaction,
  - Email/Internal/Phone ortak MIME article create yolunda DB-storage zorunlulugu ve body icermeyen normalize audit,
  - audit hata enjeksiyonunda ticket state, article row/storage, customer migration, scope version ve cache rollback kaniti,
  - tenantless create ve cross-tenant customer reassignment icin fail-closed davranis,
  - toplu active-tenant backfill ve acik onayli tek-ticket CustomerID replacement komutlari,
  - status kapisinda `UnboundTickets=0`, `InvalidTenantTickets=0`,
  - sorgu-oncesi tenant filtresi, `CustomerIDRaw` bypass reddi ve immutable-scope tekil okuma,
  - Generic Interface get/history/update ortak erisiminde OTOBO izni + tenant izni birlikte zorunlu,
  - `integration.ticket.get/history/update` operasyon-bazlı matrisi; requester/auditor update reddi ve bilinmeyen operasyon için fail-closed davranış,
  - Elasticsearch TicketSearch oncesinde trusted directory/customer context ve merkezi `search.read` karari,
  - final ortak Elasticsearch invoker'inda `CustomerID` tenant filter'i; direct unscoped ve desteklenmeyen global index sorgularinda fail-closed,
  - status kapisinda search contract/index/field/unscoped davranis raporu,
  - dört test dosyası / 109 test `PASS`.
- GPL-3.0 `D724Catalog 0.6.1`, `D724Request 0.4.8` ve `D724Commitment 0.3.8` entegrasyonu:
  - tenant-local commitment policy referansli katalog workflow'u,
  - request acilisinda immutable policy snapshot ve otomatik commitment baslatma,
  - OTOBO calisma saatleri, tatil gunleri ve calendar timezone hesaplari,
  - request status kurallarindan pause/resume ve due-time yeniden hesaplama,
  - warning/breach optimistic transition ve append-only system actor kaniti,
  - daemon tarafindan dakikada bir, tek paralel instance ile scheduled sweep,
  - tenant-admin policy ekrani; customer ve agent warning/due/status gorunumu,
  - authenticated HTTP akisi: `paused -> running -> met` ve `awaiting_approval -> in_fulfillment -> fulfilled`.
  - response/resolution/OLA hedefleri, validated-answer entitlement secimi ve idempotent escalation outbox,
  - authenticated HTTP akisi `REQ-0000000042`: iki hedef paused, onaydan sonra uc hedef running, ilk yanit ve fulfillment sonunda uc hedef met.
  - atomik lease, exponential retry ve dead-letter escalation dispatcher,
  - tenant-role OTOBO email notification, tenant-kapsamli fulfillment assignment ve allow-list/HMAC-SHA256 webhook adapter'lari.
- GPL-3.0 `D724API 0.7.1` OPM paketi:
  - tenant-bazli bcrypt client credentials ve yalniz SHA-256 digest'i saklanan kisa omurlu opaque bearer token,
  - varsayilan-reddet role/action karari ve DB-atomik istemci/dakika rate limit,
  - tenant-admin client create ile auditli, optimistic-version ve idempotent client revoke; tum tokenlarin aninda iptali,
  - OTOBO Public frontend uzerinden token, cursor'lu vaka listesi ve tek vaka JSON endpoint'leri,
  - immutable `d724_ticket_scope` SQL predicate'i; cross-tenant nesne varligini gizleyen `404`,
  - `no-store`, `nosniff`, bearer challenge ve `429 Retry-After` guvenlik basliklari,
  - secret/token yazdirmayan gercek HTTP kabulunde token/list/get `200`, bilinmeyen vaka `404`, revoke sonrasi ayni token `401`.
  - fork PSGI adapter'i ile canonical `/careoncloud/api/v1` ve public OpenAPI 3.1 kontrati,
  - aktif ve ayni tenant customer hesabi adina transaction-atomic request create ile requester-owned get,
  - `Idempotency-Key`: ilk create `201`, kalici replay `200`, farkli payload conflict `409`,
  - canonical HTTP kabulunde request `187` create/replay/conflict/get `201/200/409/200`.
  - optimistic-version secret rotation: secret hash + version + tum aktif token revoke + audit tek transaction,
  - audit hata enjeksiyonunda eski secret hash/version/token durumunun eksiksiz rollback'i,
  - token issue/revoke olaylarinda secret veya tam digest icermeyen audit fingerprint'i,
  - 30 gun token digest / 48 saat rate-window retention, confirmed cleanup komutu ve stale backlog metrikleri,
  - gercek HTTP rotation kabulunde version `2`; eski token/secret `401/401`, yeni secret/token `200/200`.
  - tenant-admin webhook subscription create/list/get/update, optimistic version ve requester default-deny endpoint'leri,
  - canonical OpenAPI 3.1 webhook subscription semalari ve route contract'i.
  - tenant + UTC minute + sabit route/method/status/error boyutlu atomik latency/error serileri; ham path, nesne ID'si ve kimliksiz istekler icin `__public__` siniri,
  - 168 saat metrik retention'i; 5 dakikalik request/error/ortalama-maksimum latency ve esik tabanli saglik raporu,
  - gercek HTTP kabulunde uc `tickets/200`, normalize `not_found/404` ve `__public__/tickets/401`; 12 bagimsiz writer tek seride count/sum/max `12/78/12`.
- GPL-3.0 `D724Webhook 0.3.0` OPM paketi:
  - tenant-safe subscription repository, exact/prefix event filtreleri ve audit-head baslangic cursor'u,
  - immutable audit scanner ile ortak D724Commitment outbox'ina transaction-atomic queue + cursor ilerlemesi,
  - `(tenant, subscription, audit sequence)` exactly-once teslimat ve crash-window idempotent recovery,
  - endpoint URL/secret icin deployment-only `endpoint::URL` / `endpoint::Secret` SysConfig modeli,
  - gercek HTTP kabulunde `403/422/201/200/200/200/409`, audit sequence `116`, outbox `74`, teslim `delivered`.
  - genel lifecycle outbox'u icin pending/retry/dead/delivered throughput, oldest-ready age ve backlog/age/dead-letter saglik alarmlari.
  - scanner her subscription tenant'i icin merkezi automation karari almadan audit okuyamaz veya cursor ilerletemez.
- GPL-3.0 `D724Commitment 0.5.0`: sweep ve ortak escalation dispatcher aktif tenant + tenant-bound automation karari olmadan state/version degistiremez veya outbox lease edemez; health bozuk runnable/dispatchable tenant referansinda fail-closed olur.
- GPL-3.0 `D724Reporting 0.2.0`:
  - request status, catalog item kullanim ve commitment objective/status sayimlari; her sorguda tenant + inclusive tarih araligi,
  - en fazla 366 gun, yalniz aggregate alanlar; requester, cevap, yorum, idempotency key ve serbest metin export edilmez,
  - JSON ve RFC4180-benzeri CSV; CR/LF temizleme ve `= + - @` spreadsheet formula neutralization,
  - her cache get/set oncesi yeniden yetkilendirme, tenant namespace'li 60 saniye aggregate cache ve schema-version'li logical key,
  - gercek demo kabulunde `10` request, `24` commitment, `2` breached; JSON/CSV PII-minimize ve cross-tenant export `FORBIDDEN`.
- GPL-3.0 `D724Identity 0.3.0` OPM paketi:
  - exact issuer/audience trust route'undan tenant türetme; token `tenant_id` claim'ini yönlendirmede yok sayma,
  - yalnız doğrulanmış OIDC/SAML adaptör sonucu kabulü; HTTPS issuer ve email-domain allow-list'i,
  - bounded grup→tenant rol eşlemesi, varsayılan requester ve bilinmeyen gruplarda yetki vermeme,
  - immutable `(provider, subject)→login`, tenant login takeover koruması ve idempotent last-seen yenileme,
  - provider/ilk subject link mutation'ı ile audit olayının transaction-atomic yazımı,
  - digest-only state/nonce/verifier saklama, PKCE S256 ve browser binding; yerel dönüş yolu ve tek-kullanımlık callback,
  - aynı-origin HTTPS discovery/JWKS ve yalnız RS256/ES256; OTOBO yerleşik JWKS/imza doğrulayıcısına delegasyon,
  - agent/customer surface bağlı web adapter'i, Secure/HttpOnly/SameSite=Lax flow cookie'si ve exact OIDC profile/redirect doğrulaması,
  - kurulumdaki mevcut DB/LDAP auth backend'ini koruyan fallback; callback sonrası preprovision ve aktif tenant üyeliği kapısı,
  - altı test dosyası / 71 test `PASS`, canlı agent/customer parola oturumları `302→200` ve status `Success=1`.
- On üç CareOnCloud paketinin 52 dosyalık birleşik regresyonu `1016` test ile `PASS`; mevcut OTOBO OAuth2 testleriyle birlikte 59 dosya / `4042` test `PASS` (`2026-07-25`).
- Gercek oturumlu HTTP kabul akisi `REQ-0000000086`: create, approve, first-response, task-completed ve fulfilled olaylari bes farkli dedupe anahtariyla kaydedildi; ayni customer POST replay'i ayni request'i dondurdu ve olay sayisi bes kaldi; tenant zinciri `Valid=1` ve request durumu `fulfilled`.
- Gercek hata enjeksiyonu `REQ-0000000102`: audit kapaliyken create icin tuketilen ID'de request/task/commitment/audit kalintisi `0`; ayni idempotency key ile retry basarili. Approval ve completed-task audit hatalarinda request/approval/task state ve version geri alindi; ayni optimistic version ile retry basarili, sonuc `fulfilled` ve uc commitment `met`.
- Concurrent dedupe kabulunde iki bagimsiz writer ayni tenant/key icin `replay=0` ve `replay=1` dondu; veritabaninda tek event, sequence/head `1` kaldi.
- Gercek katalog hata enjeksiyonu: service create audit hatasinda row `0`; update hatasinda ad/version degismedi; schema-set hatasinda schema row `0`. Ayni girdilerin retry'lari basarili oldu ve bes sirali katalog audit olayi uretildi; tenant zinciri `Valid=1`.
- Gercek directory audit hata enjeksiyonu: audit kapaliyken membership grant `AUDIT_WRITE_FAILED` ve kalici row `0`; revoke hatasinda membership `active/version=1` kaldi. Audit geri geldiginde retry'lar `version=1` ve `version=2` ile basarili oldu; zincirde yalniz `tenant.created`, `tenant.membership.granted`, `tenant.membership.revoked` olaylari kaldi ve `Verify.Valid=1`.
- Gercek OTOBO ticket kabul akisi: demo tenant ticket `D724AUD20260724001` / ID `9`, `open`, scope version `3`; `ticket.created`, `ticket.state.updated`, `ticket.article.created` olaylari ve gecerli tenant zinciri. Idempotent ikinci kabul calismasi `Created=0` ile ayni ticket ve uc olayi dondurdu.
- Legacy upgrade kabulunde bos CustomerID'li kurulum ticket'i `2015071510123456` acik replacement onayiyla `d724-demo` tenant'ina transaction-atomic atandi; iki cekirdek ticket'in ikisi de scoped, unbound/invalid sayilari `0`.
- Tarihsel OPM SHA-256 kanıtı: Audit 0.2.0 `44604ad6aeb20d5e9eda2c25b28423f2eb6082037d06061f154b8fab13d4446d`, TenantDirectory 0.2.1 `024cfa1cc1298bd00459cc6cb88ecc99e868caac1beb9fa434dd814d06be7b28`, Catalog 0.5.2 `90dfeb6309bcaa89bcffe9acff4ec7e92031afff4bec7eb34bb313343a2795e5`, Request 0.4.6 `c8b5ddb9a9a0aed10e43094f9748ea7a6aca2089f41c0097236f6b57a7c51f46`, Commitment 0.3.8 `19bb3331b3efee9c3d143673fc7537720d3d98f11fc3bf69fa24f3c9229eb94c`.
- TicketAudit 0.6.1 OPM SHA-256: `a574c4e22fef7520c7d86a7ab418f13243ae8e8963e742150b1c6d097e3d9e29`.
- D724API 0.4.0 OPM SHA-256: `801c8dae38c478b1b65e214e79198a46b69083576eade30eddef96fb5fad8ceb`.
- Son entegrasyon OPM SHA-256 kaniti: Commitment 0.4.1 `4eff743d0f69fbeb9903b664d654522da8404703ebd72de17d9aa66a151cfe69`, Webhook 0.2.0 `c378ef925121806e82c083afec1adbacb539e7399177e70a900266a953759e46`, API 0.7.1 `9c0ff5451658d4534c9b982b12d512763cf3b84662a61cc046f5d7b31c1db29a`.
- Daemon-policy OPM SHA-256 kaniti: TenantGuard 0.3.0 `590308bc72229b505d4a3b63daf04300983242150c630bed115fecafdda89962`, Commitment 0.5.0 `96091e6586fdc9f38afcd21dae66574ad17074b9a66603e0a84fdc82420e5f83`, Webhook 0.3.0 `bdd5df604e517769e41cd00b522add91f15f3cd667fda2d2971f9b0d0de8d8c5`.
- Reporting-policy OPM SHA-256 kaniti: TenantGuard 0.4.0 `c93d399a40a9d567660db9eaa91f6367d0f73e9171b2873d655ae78740f5a8bf`, Reporting 0.1.0 `4215ab125e2c531c131e839ef357f5bde0b8b7c1a24ef3e64fcaa5285fd7be57`.
- Cache-policy OPM SHA-256 kaniti: TenantGuard 0.5.1 `144045187a4cb25e2b664bafb465e3ad34130585172e6a54e672dcbf9477dc01`, Reporting 0.2.0 `4365369a9dae69a1eeae5860fb6a1ed059752fe384a902456ef9066c061ab5ca`.
- Tarihsel search-policy OPM SHA-256 kanıtı: TenantGuard 0.6.0 `66ff6f82eac72463fa22579a783e62266ef40047e29a12105b587845b45b4438`, TicketAudit 0.7.1 `6b98185191b32846d8a8e09d213996ebd28df6c49ece80717f0dd8be2418bca8`.
- SEC-01b yayın OPM SHA-256 kanıtı: TenantGuard 0.7.0 `e2c4f4d7b77f4588f4950aa7bf785abcc3ba1705eb0427a177b986ffae2cd5e2`, TicketAudit 0.8.1 `31792e68bc819ae70cfe843953260648d0f8f54187a5c8b9ef7ecbf4d1f33cb8`, Catalog 0.6.1 `867cfa4fffd094a74bc98ac4ea11675a7429db974c6ee39c8d3d00433d9bd986`.
- SEC-03a yayın OPM SHA-256 kanıtı: TenantGuard 0.8.0 `31e8de399198caa81102d989319db382c609e540aefe3e58446c82265605f975`, Identity 0.1.1 `067822c1d5b8852c8351fa36525b48b613014e2bf76cef698067c1b2f0a60a8d`.
- SEC-03b-core yayın OPM SHA-256 kanıtı: Identity 0.2.0 `38e7ae451fdd9b81eaece5019998616d8784a7f2fd52f69cfa95b609efef72ac`.
- SEC-03b-web-core yayın OPM SHA-256 kanıtı: Identity 0.3.0 `74f8ea05d04ddf7a8753a9c4ad8e2c90f022a2ac703f996f68ebc7432d345039`.
- Kalici ticket-policy kabulunde `demo.agent` (UserID `47`) kendi `d724-demo` scope'unda yalniz TicketID `9` / `D724AUD20260724001` sonucunu gordu; `CustomerIDRaw` bypass'i reddedildi ve Generic Interface ortak erisimi basarili oldu.
- Gercek Elasticsearch runtime kabulunde ayni full-text degerli `d724-demo` ve yabanci tenant fixture dokumanlarindan UserID `47` yalniz kendi hit'ini gordu; explicit cross-tenant filter `EMPTY_TENANT_INTERSECTION` ile reddedildi ve fixture'lar silindi.
- Resmi `Maint::Elasticsearch::Migration --target t` authoritative rebuild'i 2 MariaDB ticket'ini tasidi; refresh sonrasi index count `2`. Elasticsearch aktifken 42 dosya / 859 test yeniden `PASS` oldu.
- GPL-3.0 `D724Observability 0.1.0`: tenant/PII/dinamik label icermeyen 20 sabit Prometheus serisi; API latency/error-rate ile webhook backlog/age/dead-letter alarm bayraklari; Elasticsearch policy, tenant-cache, commitment ve escalation saglik sinyalleri; digest-only Bearer auth ve fail-closed `503`.
- Gercek Public frontend scrape kabulunde eksik/yanlis/dogru Bearer sonucu `401/401/200`, `d724_up=1`, 20 sabit seri, `no-store` ve secret sizintisi olmamasi dogrulandi. Test tokeni yalniz `/home/test/.d724-metrics-token` dosyasinda `0600` tutuluyor.
- Cloudflare Tunnel üzerinden `https://esm.arcak.net` yayını aktiftir; origin yalnız `127.0.0.1:8088` systemd socket proxy üzerinden özel `100.86.171.110:8088` bind'ına ulaşır. Agent ve müşteri girişleri HTTP `200` ile doğrulanmıştır.
- DD-YHE-02-R1 DORA uyumlu Careon hizmet kataloğu 6 ana alan, 51 yönetilen hizmet sunumu ve tenant başına 51 katalog öğesi olarak ürünleştirildi. Üç sentetik sektör demosunda mevcut iki sektörel öğeyle toplam `53` aktif katalog öğesi vardır.
- Sentetik Marmara Bank Demo, Anadolu Moda Demo ve Perakende360 Demo tenant'larında toplam `36` request ve `99` commitment bulunur. Yönetici raporu kullanım ile katalog kapasitesini ayrı gösterir; hiçbir ad gerçek müşteri referansı değildir.
- Elasticsearch webservice ID `1`, surumlu YAML ve idempotent konfigurator ile `http://elastic:9200` private host'una sabitlendi; OTOBO `Maint::Elasticsearch::TestConnection` basarili.
- Gelistirme kurulumunda varsayilan admin ve root parolalarinin otomatik rotasyonu.

## Bilerek ertelenen

- Test yayını Cloudflare Tunnel ve TLS ile açılmıştır; üretim öncesinde Cloudflare Access/WAF, origin sertleştirmesi, kalıcı secret yönetimi ve bağımsız güvenlik testi tamamlanmalıdır.
- GitHub Actions workflow'u depoda bulunur ancak fork icin Actions calistirma politikasi ayrica etkinlestirilmelidir.
- Katalog, cekirdek OTOBO ticket yazimlari, TicketSearch, Generic Interface ortak ticket get/history/update erisimi, D724 commitment/webhook daemon isleri, operasyon rapor/export'u, D724 cache ve aktif Elasticsearch ticket aramasi tenant scope'a baglidir. Generic Interface operasyon-bazli role/action matrisi aciktir.
- OTOBO paket şema çeviricisinin çok sütunlu foreign key sınırlaması, idempotent post-install/upgrade sertleştiricisi ve health doğrulamasıyla giderilmiştir.
- OTOBO paket upgrade'inden sonra uzun omurlu Perl web worker'lari yeniden baslatilmalidir; aksi halde ayni anda eski ve yeni adapter kodu calisabilir. Test deploy runbook'u artik `web` ve `daemon` restart + HTTP health kontrolunu zorunlu kabul eder.
- Request lifecycle, D724 katalog, tenant-directory ve kapsanan OTOBO ticket/MIME article mutasyonlari atomiktir. Ticket delete/merge/type/service/SLA/pending, Chat article, Generic Interface ve commitment scheduler gibi diger yazim adapter'lari henuz ayni transaction/outbox completeness garantisine sahip degildir.

## Henuz urun sayilmayan kapsam

Asagidaki maddeler tamamlanmadan ticari ESM `1.0` hedefi gerceklesmis sayilmaz:

- tenant/organizasyon policy siniri ve veri sizintisi testleri,
- UC hedefi ve dead-letter replay yonetim arayuzu (onayli console replay ve teslim metrikleri tamamlandi),
- tum domain adapter'larinda atomik audit completeness, retention/legal hold ve dis WORM arsivi,
- portal ve agent urun deneyimi,
- SSO/SCIM ve entegrasyon sozlesmeleri,
- AI gateway, PII korumasi ve insan onayi,
- yedek/geri donus, upgrade, SBOM ve imzali release sureci.

Bir sonraki ürün kapısı `SEC-03b-idp/SEC-03c` ve `OBS-01b`: gerçek dış IdP kabulü, logout/session politikası ve SCIM yaşam döngüsü; OpenTelemetry export'u, operasyon dashboard'u ve alarm teslim kanalları. Buna paralel kalan ticket/Chat/SLA adapter'ları, transactional outbox ve immutable dış arşivdir.
