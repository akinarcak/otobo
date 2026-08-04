# CareOnCloud ESM Durum Kaydı

## 2026-08-03 — CareOnCloud marka geçişi, güvenli ilk dilim

- `VERIFIED_BY_CURRENT_TEST`: Kullanıcıya/log’a görünen runtime hata mesajlarındaki `D724` öneki Catalog, Request, Webhook, TenantDirectory, TicketAudit ve Public API adapter’larında `CareOnCloud` olarak değiştirildi. Foundation kapısı geçti; commit `c6b676206`.
- `RISK`: Paket adları, Perl namespace’leri, DB tabloları, config anahtarları, SOPM yolları ve sabit API error code’ları teknik sözleşmedir; bunlar migration/upgrade planı olmadan değiştirilmedi. Depoda kalan `D724` referansları korunmuş compatibility kimlikleridir.

## 2026-08-03 — P0 TicketAudit runtime kabulü

- `VERIFIED_BY_CURRENT_TEST`: Sabit uzak test script'iyle 18 D724 paketinin tamamı ardışık olarak çalıştırıldı ve her paket `All tests successful` döndürdü. D724TicketAudit 227, API 160 ve Reporting 73 test dahil edildi; negatif-path SQL/policy logları beklenen assertion kanıtıdır.

- `VERIFIED_BY_CURRENT_TEST`: Kalan iki TicketAudit failure transaction-depth kaybı değildi. Başarılı unknown-channel mutation sonrasında ticket/article cache temizlenmediği için GI rollback snapshot'ı stale kalıyordu; merge içindeki farklı Ticket nesnesinin unlock-timeout adapter'ı ise global merge suppression'ını aşarak version-2 dedupe anahtarını tüketiyordu.
- `VERIFIED_BY_CURRENT_TEST`: `9ec8f132a` cache invalidation ve merge audit ownership düzeltmesi izole aday ortamına kuruldu. D724TicketAudit 4 dosya / 227 test `PASS`; Foundation 18 paket manifesti/dosya listesi kapısı da `PASS`. Expected fail-closed policy logları test failure değildir. Aktif `d724-esm-*` servisleri değiştirilmedi.

## 2026-08-02 — P0 temiz aday paket regresyonu

- `VERIFIED_BY_CURRENT_TEST`: Temiz aday MariaDB/Redis/web ortamında 18 D724 SOPM paketi yeniden build/install edildi; kurulum döngüsü tamamlandı. Paket testlerinde Foundation, TenantGuard, Audit, TenantDirectory, Catalog, Request, Problem, CMDB, Change, Commitment, Webhook, Identity, SCIM, Assist ve Observability paketleri `PASS` oldu.
- `RISK`: Temiz adayda D724TicketAudit (227 test), D724API (160 test) ve D724Reporting (73 test) paketleri `FAIL` oldu. TicketAudit artık parser derleme hatası vermiyor; kalan sonuçlar runtime/fixture regresyonu olarak ayrıştırılmayı bekliyor. P0 tam runtime kabulü tamamlanmış değildir.
- `VERIFIED_BY_CURRENT_TEST`: `23492cc01` düzeltmeleri adayda etkinleştirildikten sonra D724API `160/160 PASS` oldu. D724Reporting `73` testte 2 assertion ile sınırlı kaldı; Reporting SQL derleme hatası giderildi, kalan iki assertion ayrı inceleniyor.
- `VERIFIED_BY_CURRENT_TEST`: Reporting kolon etiketlerindeki ikinci Perl `map` öncelik hatası `9ee4e52eb` ile düzeltildi; temiz adayda D724Reporting `73/73 PASS` oldu.
- `RISK`: TicketAuditStatus JSON incelemesi, `quick_setup.pl` tarafından oluşturulan legacy ticket `ID=1` için `UnboundTickets=1` ve `InvalidTenantTickets=1` döndüğünü kanıtladı. Aday lifecycle, paket testlerinden önce bu development fixture'ını tenant kapsamına almalı veya güvenli biçimde temizlemelidir; üretim servisine dokunulmadı.
- `FIX_APPLIED`: Temiz lifecycle runbook'una `Clean-QuickSetupTicket.pl` eklendi. Yalnız `2015071510123456` quick-setup ticket'ını core Ticket API ile paket aktivasyonundan önce temizler; üretim/aktif servis verisine uygulanmaz. Yeni lifecycle kabulü henüz çalıştırılmadı.
- `VERIFIED_BY_CURRENT_TEST`: Adayda aynı script, audit wrapper'ını yalnız fixture temizliği için suppress ederek ticket `ID=1`'i sildi; `Admin::D724::TicketAuditStatus --json` artık `Success=1`, `CoreTickets=0`, `UnboundTickets=0`, `InvalidTenantTickets=0` döndü.
- `RISK`: TicketAudit `TicketAudit.t` içinde kalan failures, Generic Interface başarısız update sonrasında `TicketTitleUpdate` mutasyonunun geri alınmaması ve merge source event zinciri üzerindedir; transaction-depth çözümü tasarım incelemesi bekler.

## 2026-08-02 — P0 aday paket regresyonu

- `VERIFIED_BY_CURRENT_TEST`: İzole aday Compose ortamında 18 D724 SOPM paketi başarıyla build/install edildi; paket listesi tüm paketleri `OK` bildirdi ve aday web yeniden başlatma sonrasında healthy kaldı.
- `FIX_APPLIED`: `D724TicketAudit` runtime testindeki iki `scalar grep` ifadesi Test2 parser'ında derleme hatası oluşturuyordu; grep sonucu parantezlenerek belirsizlik giderildi. Foundation statik kapısı tekrar geçti.
- `RISK`: D724TicketAudit tam runtime test paketi bu düzeltme aday image'a yeniden paketlenip kurulmadan tekrar koşulmadı. İlk denemede TicketAuditStatus taze DB fixture eksikliği nedeniyle 5 assertion, TicketAudit.t ise parser hatası nedeniyle durdu; P0 runtime kabulü henüz tamamlanmadı.

## 2026-08-02 — P0 BuildKit aday image üretimi

## 2026-08-02 — P0 izole aday web health kabulü

- `VERIFIED_BY_CURRENT_TEST`: The candidate image `d724/esm:candidate-dd198c0da` was started in the separate Compose project `careoncloud-candidate-dd198c0da` with new MariaDB, Redis, application, and update volumes and host port `127.0.0.1:18080`. MariaDB and Redis reported healthy; the CareOnCloud web container reported healthy and served `GET /health` with HTTP 200. The active `d724-esm-*` project remained unchanged. This is isolated startup/health evidence only; the 18-package lifecycle, authenticated UI, and MariaDB business-regression suite remain open.

- `VERIFIED_BY_CURRENT_TEST`: On the test server, user-local Docker Buildx `v0.34.1` built `d724/esm:candidate-dd198c0da` from commit `dd198c0dace3a8573fa3946c3651e52517993edb`. The image digest is `sha256:56001da61bf1b66576a85fdc3b33d5c0068bf0bc3da384ed0603aea66514d4ec` and its OCI revision label matches the exact source commit. The Linux build required the repository `.gitattributes` fix forcing `bin/docker/carton` to LF; no source/runtime semantics were changed. This proves candidate image construction and source-to-image provenance only; no candidate Compose lifecycle, MariaDB acceptance, or cutover was run.
- Cleanup: obsolete candidate archives/checkout, reclaimable BuildKit cache, unused clean app volumes, and (with explicit user approval) the stale non-CareOnCloud `d724/esm:dev` image were removed after the build. Active `d724-esm-*` containers, ESM/DB volumes, candidate image, and preserved historical shallow checkout were not removed. Active container IDs/statuses were unchanged; free space after cleanup is 4.4G.

## 2026-08-02 — P0 runner read-only doğrulaması

- `VERIFIED_BY_CURRENT_TEST` (read-only runner probe): `test@100.86.171.110` accepted the configured test credentials. Docker Compose `2.40.3` is available, filesystem free space is `4.7G`, and the expected active containers are `d724-esm-elastic-1`, `d724-esm-daemon-1`, `d724-esm-web-1`, `d724-esm-redis-1`, and `d724-esm-db-1`. `docker buildx` is unavailable, so no candidate build or lifecycle was started. No active service was changed.

## 2026-08-02 — P0 statik kapı yeniden doğrulaması

- `VERIFIED_BY_CURRENT_TEST`: Current clean commit `a5ea92d7c7bce7ff89c75966cca4d471f5a159a3` passed `Test-CareOnCloudBrand.ps1` (16 required paths, 15 forbidden paths, 18 packages), `Test-CriticalLanguage.ps1` (2 protected customer/agent journeys), and `Test-CpanSbom.ps1` (201 components). These are source/metadata contracts only; authenticated runtime and current candidate MariaDB acceptance remain open.
- Runner note: the configured test-server SSH key was not accepted in this session; no remote mutation was attempted. The documented BuildKit-capable runner remains the next P0 runtime prerequisite.

## 2026-08-02 — P0.5 lisans metadata tutarlılığı

- `VERIFIED_BY_CURRENT_TEST`: OCI image license labels in the CareOnCloud web, Alpine web, nginx, Elasticsearch, and Selenium Dockerfiles are now the SPDX value `GPL-3.0-only`. The foundation gate rejects the prior `GNU General Public License v3.0 or later` label, keeping release-image metadata aligned with the repository license policy. This is a repository metadata contract, not legal advice.
- `VERIFIED_BY_CURRENT_TEST`: CareOnCloud kaynak ve paket politikası `GPL-3.0-only` olarak tekleştirildi. D724 paket kaynak başlıkları, Foundation tanılama manifesti, API kontratı ve ticari politika zaten bu tanımla uyumluydu; root README ve NOTICE'daki eski `GPL-3.0-or-later` ifadesi `GPL-3.0-only` olarak düzeltildi. SOPM'lerin tam GPL v3 metadatası (`GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007`) aynı lisans tercihini taşır.
- `Test-Foundation.ps1` artık README, NOTICE ve GPL-COMMERCIAL politikasında açık `GPL-3.0-only` tanımını ve çelişen `GPL-3.0-or-later` ifadesinin yokluğunu; tüm D724 SOPM manifestlerinde de kanonik GPL v3 metadatasını zorunlu kılar. Upstream telif ve GPL bildirimleri korunur. Bu bir hukuki görüş değil, depodaki metadata sözleşmesidir.

## 2026-08-02 — P0.5 kritik TR/EN kaynak sözleşmesi

- `VERIFIED_BY_CURRENT_TEST` (static only): `Test-CriticalLanguage.ps1` passed on the current `606eb6f` source snapshot for the two protected customer/agent journeys. This verifies UTF-8 and required translation keys in the selected source templates; it is not an authenticated runtime localization acceptance.
- `VERIFIED_BY_CURRENT_TEST`: Müşteri Hizmet Kataloğu ve ajan Operasyon Merkezi için kaynak-temelli TR/EN kapısı eklendi. `Test-CriticalLanguage.ps1`, şablondaki sabit `Translate(...)` anahtarlarının ilgili `tr_D724*` sözlüğünde bulunmasını, dosyaların katı UTF-8 olmasını ve yaygın mojibake işaretlerini içermemesini doğrular. Operations Center'daki eksik `Please select` çevirisi `Lütfen seçin` olarak tamamlandı. Bu statik sözleşme, authenticated runtime portal/agent kabulünün yerini tutmaz.

## 2026-08-02 — P0.4 dashboard runtime marka düzeltmesi

- `VERIFIED_BY_CURRENT_TEST` (static only): `Test-CareOnCloudBrand.ps1` passed on the current `606eb6f` source snapshot, checking 16 required product paths, 15 forbidden runtime-brand paths, and 18 package directories. This is source contract evidence only; authenticated runtime screens and generated emails remain separate acceptance work.
- `VERIFIED_BY_CURRENT_TEST`: Framework dashboard'un kullanıcıya görünen varsayılan `OTOBO 11.1` başlığı, açıklaması ve upstream bağlantısı CareOnCloud ESM metni ile ürün bağlantısına çevrildi. Kaynak marka sözleşmesi bu ayarları doğrular. Aday runtime'da authenticated agent dashboard render kabulü henüz çalıştırılmamıştır.

## 2026-08-02 — P0.4 varsayılan e-posta ve müşteri yüzeyi marka düzeltmesi

- `VERIFIED_BY_CURRENT_TEST`: Varsayılan agent/customer parola ve yeni hesap bildirimleri CareOnCloud ESM adıyla güncellendi. Customer login/dashboard metinleri CareOnCloud ESM'e çevrildi; upstream News dashboard backend'i varsayılan olarak kapatıldı ve CareOnCloud duyuru metni aldı. Kaynak marka sözleşmesi bu aktif varsayılanları denetler.
- `VERIFIED_BY_CURRENT_TEST`: yeni isimli, taze MariaDB/Redis/application volume adayında `quick_setup.pl` sonrası `Admin::Config::Read`, bildirim adını `CareOnCloud ESM Notifications`, customer login/dashboard metinlerini CareOnCloud olarak ve News backend `Default: '0'` ile geri okudu. Kanıt: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/brand-sysconfig-acceptance.log`. Geçici `d724-brand-sysconfig-20260802` Compose projesi, network ve yalnız kendi volume'ları kaldırıldı; aktif `d724-esm` servisleri değiştirilmedi. Bu kabul persisted eski kurulumların upgrade migration'ını veya authenticated HTML render'ını kapsamaz.

## 2026-08-02 — P0 release CPAN SBOM kapısı

- `VERIFIED_IN_CODE` / `TEST_EXISTS_NOT_RERUN`: the Foundation workflow adds Trivy gates for fixed HIGH/CRITICAL findings in both repository dependency metadata and the `d724/esm:dev` image built by the clean lifecycle, covering OS and library scanners and uploading JSON results even when a gate fails. The image scan still depends on a successful BuildKit-capable candidate build and does not attest the base-image digest or sign the image.
- `VERIFIED_BY_CURRENT_TEST`: `Generate-SourceArtifact.ps1` refuses a dirty worktree, creates a commit-bound CareOnCloud source ZIP, and writes a SHA-256 manifest with the exact commit and D724 package version inventory. Its contract test passed on the clean `ead154803` source snapshot, verifying the archive hash, current commit, and package inventory; the Foundation workflow uploads both as a release-evidence artifact. This is provenance evidence, not a signed artifact or reproducible-image proof.
- `VERIFIED_IN_CODE`: the Foundation workflow now supports manual `workflow_dispatch` in addition to its path-filtered push/PR triggers, and includes every CareOnCloud root Dockerfile, development Dockerfile, locked CPAN snapshot, and repository license/security input its gates inspect. A change to those release inputs therefore triggers the same static Foundation, brand, SBOM, and clean-package workflow instead of silently bypassing it. GitHub Actions execution for the fork remains unverified.
- `VERIFIED_BY_CURRENT_TEST`: `Generate-CpanSbom.ps1`, Docker web build'inde deployment modunda kullanılan kilitli `cpanfile.docker.snapshot` kaynağından deterministik CycloneDX 1.5 CPAN dependency SBOM'u üretir. `Test-CpanSbom.ps1` formatı, component sayısını ve her CPAN purl'ını doğrular; CI artifact'i olarak yükler. Kapsam yalnız CPAN build distributions'tır: Debian/OS paketleri, base-image digest'i, container image inventory, vulnerability scan ve imzalı release artifact henüz tamamlanmamıştır.

## 2026-08-02 — P0.2 tenant yol ve negatif test envanteri

- `VERIFIED_IN_CODE`: `security/TENANT-PATH-MATRIX.md`, merkezi policy, directory, katalog, request, API, ticket/GI, search, cache, reporting, webhook ve scheduler yollarini ilgili test/kabul artefaktlariyla esler. Native OTOBO ekranlari, tum Generic Interface operasyonlari, diger daemonlar ve platform-admin bypass'i acikca `PARTIAL` olarak isaretlenmistir; bu nedenle tam tenant izolasyonu iddiasi yoktur.

## 2026-08-02 — P0 CareOnCloud security policy

- `VERIFIED_IN_CODE`: root `SECURITY.md` upstream-only/fork-excluding policy yerine CareOnCloud kapsamı, private GitHub vulnerability reporting URL'i, 3 is gunu acknowledgement, 7 takvim gunu critical response hedefi, CVE koordinasyonu ve managed customer bildirimini tanimlar. Foundation kapisi bu zorunlu terimleri ve eski `security@otobo.org`/fork-exclusion dilinin yoklugunu denetler. `VERIFIED_BY_CURRENT_BROWSER`: repository owner oturumunda `Settings > Advanced Security` ekrani kaydedilmis ayari `Disable private vulnerability reporting` dugmesiyle gosterdi; private reporting etkindir. Versioned release oncesi supported-version bakim taahhutleri ayri olarak somutlastirilmalidir.

## 2026-08-02 — P0 logical database backup/restore acceptance

- `VERIFIED_BY_CURRENT_TEST`: taze, ayrik MariaDB/Redis/application-volume adayinda `careoncloud_esm` database'i mantiksal olarak `mariadb-dump --single-transaction --routines --events` ile alindi ve farkli, once bos `careoncloud_restore_probe` database'ine geri yuklendi. Kaynak ve restore table sayilari `139/139` esitti; restore edilen probe kaydi okundu ve dump SHA-256 kaydedildi. Kanit: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/backup-restore-acceptance.log`. `d724-backup-restore-20260802` aday projesinin sadece kendi DB/app/update volume'lari, container'lari, network'u ve dump'i silindi; aktif `d724-esm` degismedi. Bu kanit logical MariaDB restore kapsar; application volume restore, RPO/RTO olcumu, encrypted/off-host backup ve production cutover kapsami disindadir.
- `VERIFIED_BY_CURRENT_TEST`: iki yeni, gecici Docker application volume'unda olusturulan probe dosya agaci tar archive ile backup alindi ve bos hedef volume'e restore edildi; probe SHA-256 degeri esitti. Kanit: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/application-volume-restore-acceptance.log`. Kaynak archive ve iki aday volume islem sonunda silindi; bu sadece Docker volume tar/restore mekanizmasini kapsar, gercek uygulama volume'u, encrypted/off-host backup, RPO/RTO ve blue/green cutover kapsamini kapsamaz.

## 2026-08-02 — P0 migration execution safety

- `VERIFIED_BY_CURRENT_TEST`: copy migration betiği artık execute modunda açık `--compose-project` ve `--allow-writer-stop` onayı olmadan çalışmaz. Kaynak volume'lar var olmalı; hedef volume/database yoksa fail-closed olur. Mantıksal dump SHA-256 değeri ve rollback yönü sonuç kaydına yazılır. Test sunucusunda Bash syntax ve non-mutating plan modu çalıştı. Bu, backup restore/RPO/RTO provası değildir.

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

- `VERIFIED_IN_CODE` / `RISK`: GenericAgent's `AutoPriorityIncrease` path reaches the audited `TicketPrioritySet` wrapper. `D724TicketAudit 0.8.14` additionally wraps `GenericAgent::JobRun`, runs it per active tenant inside `AutomationScopeRun`, and lets the existing TicketSearch policy apply the automation tenant filter before selection. A clean candidate cross-tenant GenericAgent acceptance is still required; no daemon runtime or request-atomicity claim is made yet.
- `TEST_EXISTS_NOT_RERUN`: the clean candidate lifecycle now includes a two-tenant GenericAgent acceptance. It targets tenant A through a GenericAgent customer criterion, verifies that only tenant A's ticket priority changes while an identically titled tenant B ticket remains unchanged, then verifies the normalized audit event and tenant A chain. It requires a current CareOnCloud candidate before it becomes runtime evidence.
- `VERIFIED_BY_CURRENT_TEST` (syntax only): the current `7ac0169` source snapshot compiled `Accept-GenericAgentTenantScope.pl` in an isolated container using the test server's available Perl runtime. This establishes only script loadability, not GenericAgent selection, scheduler execution, tenant isolation, MariaDB persistence, or rollback behavior.
- `VERIFIED_BY_CURRENT_TEST` (syntax only): the current `8db2629` source snapshot compiled `D724AuditCustom` and `D724::TicketAudit` in an isolated container using the test server's available Perl runtime. This confirms only syntax-level loadability of the GenericAgent wrapper, not scheduler, tenant, MariaDB, or rollback behavior.
- `VERIFIED_IN_CODE`: [Indirect ticket write-route inventory](security/TICKET-AUDIT-INDIRECT-ROUTES.md) confirms that Generic Interface TicketCreate/TicketUpdate and several event modules call the standard wrapped ticket methods. Generic Interface `TicketUpdate` additionally has request-level transaction coverage; scheduler and daemon routes remain separate.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.6` adds transaction-aware Chat `ArticleCreate` coverage. Candidate MariaDB regression `TicketAudit.t` passed 115 tests, including audit-disabled chat article rollback, successful scope-version advancement, and normalized `ticket.chat_article.created` evidence. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/ticket-audit-0.8.6-test.log`.
- `VERIFIED_IN_CODE` / `RISK`: Email, Internal, and Phone article backends inherit the wrapped MIMEBase create path; the separate Chat backend has its own wrapped lifecycle. `D724TicketAudit 0.8.19` retains the Invalid fallback backend's unknown-channel metadata delete route with a scope/audit transaction and normalized deletion event. Candidate runtime regression is still required before that route is accepted.
- `VERIFIED_IN_CODE` / `TEST_EXISTS_NOT_RERUN`: `TicketAudit.t` now exercises the Invalid fallback delete transaction directly: an audit-disabled call must roll its backend mutation and scope version back, while the recovered call must advance the scope once and emit exactly one normalized `ticket.unknown_channel_article.deleted` event. `Test-Foundation.ps1` locks these regression assertions and passed locally for all 18 package manifests. A current candidate MariaDB run is still required before runtime acceptance is claimed.
- `VERIFIED_BY_CURRENT_TEST` (static only): `D724TicketAudit 0.8.19` keeps the status command, module versions, regression, and manifest aligned; `Test-Foundation.ps1` rejects future drift. Runtime command execution remains part of the current candidate rerun.
- `VERIFIED_IN_CODE` / `TEST_EXISTS_NOT_RERUN`: direct core comparison found `TicketArchiveFlagSet` missing from the earlier business-mutation inventory. `D724TicketAudit 0.8.19` retains its scope-lock/audit transaction wrapper. `TicketAudit.t` requires audit-disabled flag and scope rollback, recovered persistence, one scope-version advance, and exactly one normalized `ticket.archive_flag.updated` event. Foundation locks the contract; current candidate MariaDB execution is still required. Personal watcher/seen flags, accounted-time writes, escalation-index maintenance, and article-storage switching are not claimed covered.
- `VERIFIED_IN_CODE` / `TEST_EXISTS_NOT_RERUN`: the higher-model decision for `TicketUnlockTimeoutUpdate` selects two consecutive audit mutations. Direct calls use the standard scope-lock contract. `TicketLockSet`, MIMEBase, and Chat parents propagate nested mutation failure, roll the whole parent operation back, and re-lock the current scope after a successful nested timeout before recording their own event. Nested execution is enabled only for the lock setter; other generic setter suppression boundaries are unchanged. Targeted timeout-only audit injection requires lock/article, timeout, scope, and orphan-event rollback; successful parents advance two consecutive versions. The regression also replaces stale hardcoded post-archive scope assertions with runtime baselines. Foundation passed statically; current candidate MariaDB execution is still required.
- `VERIFIED_BY_CURRENT_TEST` (static only): a full primary status audit found and corrected stale package identities in `D724Catalog` (`0.6.1` to `0.7.0`), `D724Reporting` (`0.3.1` to `0.4.1`), and `D724Request` (`0.4.6` to `0.4.9`). `Test-Foundation.ps1` now compares every package's primary status source and regression, when present, with its SOPM manifest version. OpenAPI `3.1.0` and the TenantGuard cache-adapter `0.1.0` are separate contract versions and remain unchanged. Runtime status command execution remains part of the current candidate rerun.
- `VERIFIED_BY_CURRENT_TEST` (syntax only): the current `b6404f4` source snapshot compiled `D724::TicketAudit` and `D724AuditCustom` in an isolated container using the test server's available Perl runtime. This establishes only syntax-level loadability of the Invalid-delete wrapper, not unknown-channel persistence, audit rollback, or tenant behavior.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.7` wraps Chat `ArticleUpdate` and `ArticleDelete` in the same scope-lock, transaction, and normalized-audit contract. Candidate MariaDB regression passed `TicketAudit.t` (124) and `TicketAuditStatus.t` (11), including audit-disabled update/delete rollback, successful scope-version advancement, and the complete chat lifecycle evidence. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/ticket-audit-0.8.7-rerun.log`. `RISK`: Chat update triggers core search indexing, which remains outside the MariaDB transaction boundary.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.9` wraps Generic Interface `TicketUpdate::Run` in a request-level transaction and gives nested ticket mutations savepoints. Candidate MariaDB regression passed `TicketAudit.t` (128) and `TicketAuditStatus.t` (11), including a later request failure that rolls an earlier successful title mutation, scope version, audit record, and cache state back. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/ticket-audit-0.8.9-gi-atomicity.log`.
- `VERIFIED_BY_CURRENT_TEST`: an isolated clean MariaDB/Redis/web candidate installed the Foundation/TenantGuard/TenantDirectory/Audit/TicketAudit chain, rotated the fresh `admin` password to a random process-scoped value, and accepted a real authenticated two-field REST `TicketUpdate` through `/careoncloud/nph-genericinterface.pl`. The persisted title and priority were re-read after cache invalidation, scope version advanced from 1 to 3, both normalized audit actions were present, and the tenant audit chain verified. The temporary provider and the exact Compose project, network, and volumes were removed; active `d724-esm` services remained healthy. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/gi-http-acceptance.log`. The committed clean-lifecycle CI gate now retains the same contract; a GitHub Actions run is still unverified.
- `VERIFIED_BY_CURRENT_TEST`: `D724TicketAudit 0.8.12` runs the core `Maint::Ticket::PendingCheck` command once per active tenant with a TenantGuard-authorized automation context. It records state changes through a scope-lock/audit transaction after the core pending check, so the scheduler worker's forced package reload cannot bypass the tenant scope or immutable audit update. A fresh isolated Compose project ran the actual `SchedulerTaskWorker` fork and Cron handler: the pending ticket transitioned to `closed successful`, scope advanced from 3 to 4, the normalized state audit event was present, and the tenant chain verified. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/scheduler-pending-check-acceptance.log`. The temporary project and volumes were removed; active `d724-esm` services were not changed. This accepts only the core pending-check scheduler route, not GenericAgent, other daemon jobs, direct database writes, or external side effects.
- `VERIFIED_IN_CODE` / `TEST_EXISTS_NOT_RERUN`: `D724TicketAudit 0.8.13` wraps Generic Interface `TicketCreate::Run` in the same request-level transaction model as `TicketUpdate`; nested ticket/scope/audit mutations use savepoints. Its regression makes the inner ticket creation succeed, then forces the enclosing request to fail and asserts that no ticket row remains. A current candidate MariaDB rerun is required before this route is accepted.
- `VERIFIED_BY_CURRENT_TEST` (syntax only): the current `99993f8` source snapshot compiled both `D724::TicketAudit` and its `D724AuditCustom` wrapper in an isolated container using the test server's Perl runtime. This confirms the new wrapper is loadable at Perl syntax level; it is not MariaDB transaction or HTTP acceptance evidence.
- `TEST_EXISTS_NOT_RERUN`: the clean candidate lifecycle acceptance now configures a temporary HTTP REST `TicketCreate` route alongside `TicketUpdate`, creates a tenant-bound customer user, and verifies the created ticket's tenant scope, normalized `ticket.created` audit event, and tenant chain after an authenticated HTTP request. It must run against a current CareOnCloud image before it is evidence.
- `VERIFIED_BY_CURRENT_TEST` (syntax only): the current `0ea96a4` source snapshot compiled `Accept-GenericInterfaceTicketUpdate.pl` in an isolated container using the test server's available Perl runtime. This establishes only that the expanded lifecycle acceptance script is syntactically loadable; it is not an HTTP, MariaDB, or current-CareOnCloud-image acceptance result.

## 2026-08-02 — P0.4 candidate package-install gate

- `VERIFIED_IN_CODE` / `TEST_EXISTS_NOT_RERUN`: `Test-CleanPackageLifecycle.ps1` now builds and installs all 18 current D724 OPM packages in dependency order on a fresh candidate, requires 18 healthy deployment records, and runs every package's UnitTest suite after install. D724Problem is additionally tested before and after uninstall/reinstall. Package-wide upgrade/uninstall acceptance is still open and must not be inferred from this clean-install gate. A current CareOnCloud image is required to run the expanded lifecycle.
- `RISK` / candidate-image provenance: the isolated attempt used the test server's `d724/esm:dev` tag (`sha256:f65ec8a0160d08c501bd1d3d22228b485c467231c9acda8c8fa58b773ecbd813`), but direct image inspection proved it lacks `/opt/careoncloud_install` and is not a CareOnCloud runtime image. Its `/otobo/index.pl` setup output and post-restart health failure therefore do **not** establish a source regression; authenticated CareOnCloud login/dashboard branding remains unaccepted. Evidence: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/authenticated-brand-acceptance.log`. The exact temporary Compose project, network, and volumes were removed; active `d724-esm` containers remained healthy. A historical `d9084ad` source snapshot had been prepared, but its first replacement image build did not finish within 10 minutes while the server had only 2.4 GB free; a current read-only `df -h /` check on 2026-08-02 found only 2.1 GB free. On 2026-08-02, an unused 661 MB partial candidate tree and 3.647 GB inactive build cache were removed only after proving no running container mounted the tree; free space became 5.2 GB and the preserved old image was not deleted. A manual source build then used Docker's legacy builder, which silently treated Dockerfile heredoc `RUN` bodies as empty and failed at the later `local::lib` check; Docker Compose 2.40.3 is present but the server has no `docker buildx` component. That legacy-builder result is tooling evidence only, not a source dependency or runtime regression. A BuildKit-capable candidate runner remains required. `Test-CleanPackageLifecycle.ps1` now asserts the mounted and image-side canonical PSGI files before setup, so a similarly stale image fails before package or brand evidence is claimed.
- `VERIFIED_IN_CODE`: the clean lifecycle acceptance now injects the exact checked-out Git commit into the Compose build and rejects an image unless its immutable `git-commit.txt` records that same commit, in addition to checking the canonical CareOnCloud PSGI files. This is a source-to-image provenance gate; it still requires a Docker-capable runner with sufficient disk to produce current runtime acceptance.
- `VERIFIED_IN_CODE`: `Test-CleanPackageLifecycle.ps1` now requires `docker buildx version` before creating candidate containers and fails with an explicit remediation when only the legacy builder is available. This prevents the server-side heredoc failure from being misclassified as an application regression.
- `VERIFIED_IN_CODE`: `Invoke-D724Dev.ps1` applies the same Buildx preflight to its `Build` and `Up` actions, so local candidate image creation cannot silently use the incompatible legacy builder.

- `VERIFIED_BY_CURRENT_TEST`: `Test-CareOnCloudBrand.ps1` passed against the current checkout (16 required CareOnCloud paths, 15 forbidden legacy paths, and all 18 package manifests). The D724 foundation workflow now runs this source-contract check. This is a static source guard, not proof that a running candidate has no upstream brand residue in headers, cookies, logs, emails, or rendered pages.
- `VERIFIED_BY_CURRENT_TEST`: a fresh isolated runtime candidate served `/careoncloud/index.pl` with `X-CareOnCloud-Login`, `CareOnCloudBrowserHasCookie`, and a `CareOnCloud ESM` product header. Its visible login response contained no `OTOBO` or `OTRS` token after preserving the upstream copyright comments required in the rendered source. Artifact: `/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/runtime-brand-acceptance.log`. The temporary Compose project and volumes were removed; active `d724-esm` services were not changed. This acceptance covers the anonymous login response only, not authenticated portal/agent/admin screens, email, logs, or external integrations.
- `VERIFIED_BY_CURRENT_TEST`: the D724 GitHub Actions workflow now triggers for every `packages/D724*/**` change, as well as framework and container-entrypoint changes that affect package deployment. `Test-Foundation.ps1` validates all 18 current D724 package manifests, tracked file-list entries, GPL metadata, XML well-formedness, and the framework-required `otobo_config` root/init values. Local no-Docker validation passed on 2026-08-02; this is a static CI gate, not evidence that GitHub Actions is enabled for the fork or that every package lifecycle runs in CI.
- `VERIFIED_BY_CURRENT_TEST`: the local CI gate scans D724 packages, development/release files, documentation, GitHub configuration, framework/runtime trees, and root CareOnCloud Docker/CPAN release inputs for committed private-key blocks, AWS access-key identifiers, and GitHub token identifiers. The inherited upstream S/MIME unit-test fixture file and canonical `scripts/test/sample` fixture subtree are excluded because they contain test certificates/keys rather than release credentials; runtime and release inputs remain fail-closed. The expanded gate passed on 2026-08-02. This remains a narrow high-confidence secret-material guard, not a replacement for a dedicated entropy-aware repository secret scanner or dependency/SBOM tooling.
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

Son dogrulama: `2026-08-02` (kaynak/statik kapilar ve aday sunucu durum kontrolleri; guncel runtime image kabulü bekliyor)

## Kaynakta dogrulanan ve runtime kaniti sinirli

- OTOBO `rel-11_1` tabanli GitHub forku ve `codex/esm-foundation` gelistirme dali.
- Kaynak ve paket kapilari dogrulandi; guncel `d724/esm:dev` CareOnCloud image runtime kabulü BuildKit-capable runner bekliyor.
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

## 2026-08-03 - CareOnCloud marka gecisi, admin status dili

- `VERIFIED_BY_CURRENT_TEST`: Admin status komutlarinin kullaniciya gosterilen aciklama ve metin basliklari `CareOnCloud` olarak guncellendi (Audit, Commitment, Observability, Reporting, TenantDirectory ve Webhook). Foundation kapisi gecti.
- `RISK`: Paket adlari, Perl namespace'leri, DB tablolari, config anahtarlari, SOPM yollari ve sabit API error code'lari teknik uyumluluk kimlikleri olarak korunmustur; bu fazda genis kapsamli rename yapilmamistir.

## 2026-08-03 - CareOnCloud marka gecisi, genisletilmis admin dili

- `VERIFIED_BY_CURRENT_TEST`: API, Catalog, Commitment, Reporting, Request, TenantGuard, TenantCache ve TicketAudit admin komutlarinin kullaniciya gorunen aciklama/basliklari `CareOnCloud` olarak guncellendi. Foundation kapisi gecti; teknik TicketAudit status kontrati uyumluluk etiketiyle korundu. Commit `6ccda1eb6`.

## 2026-08-03 - CareOnCloud marka gecisi, tenant admin aciklamalari

- `VERIFIED_BY_CURRENT_TEST`: Ticket scope backfill/assign ve tenant membership/bootstrap admin komutlarinin gorunen aciklamalari `CareOnCloud` olarak guncellendi; Foundation kapisi gecti. Commit `d718c53c1`.

## 2026-08-03 - CareOnCloud marka gecisi, kalan status aciklamasi

- `VERIFIED_BY_CURRENT_TEST`: TenantDirectoryStatus aciklamasindaki son gorunen `D724` ifadesi `CareOnCloud` olarak degistirildi. CareOnCloud brand contract ve Foundation kapilari gecti. Commit `8bf42601b`.

## 2026-08-03 - Aday ortam saglik ve surum kaniti

- `VERIFIED_BY_CURRENT_TEST`: `test@100.86.171.110` uzerinde aday web `healthy`, db/redis `healthy`, daemon `Up`; disk kullanimi `%76` (6.5 GB bos). Aktif `d724-esm-*` servisleri degistirilmedi.
- `GAP`: Aday imaji halen `d724/esm:candidate-f00f22e7b`; yerel son commit `473f71d32` oldugu icin son marka dilimi henuz adaya aktarilmamistir. Sunucu dirty kaynak agaci ezilmeden aktarim bekliyor.

## 2026-08-03 - P0 dil ve kaynak artefakti kapilari

- `VERIFIED_BY_CURRENT_TEST`: CriticalLanguage iki müşteri/agent yolunu geçti; SourceArtifact sözleşmesi commit `95b53b12103bbd608dda691b0b08c021b06318e3` için manifestli ZIP üretti ve doğruladı.

## 2026-08-03 - Aday tekrar regresyonu, kirli fixture sinyali

- `RISK`: Aday `candidate-f00f22e7b` icinde gercek 18 paket regresyon scripti calistirildi. Foundation, TenantGuard, Audit, TenantDirectory, Catalog ve Request dahil onceki paketler `PASS`; TicketAudit toplam 227 testte `TicketAuditStatus.t` 11 testten 5 failure ile kosuyu durdurdu. Hatalar saglik status snapshot'inda yetim/eski ticket fixture'lari oldugunu gosteriyor. Yeni marka commitleri bu imajda yoktur.
- `NEXT`: Aday MariaDB/volume fixture'larini aktif `d724-esm-*` servislerinden tamamen ayri temiz bir aday lifecycle ile yeniden kurup regresyonu tekrarla.

## 2026-08-03 - Aday fixture temizligi ve yeniden baslatma gap'i

- `VERIFIED_BY_CURRENT_TEST`: Yalnizca `careoncloud-candidate-f00f22e7b` Compose projesinin container/volume'lari kaldirildi; aktif `d724-esm-*` container/volume'lari ve Yetka verileri degistirilmedi.
- `GAP`: Aday yeniden baslatma, compose'un zorunlu `D724_DB_ROOT_PASSWORD` interpolation'i icin mevcut secret'in guvenli aktarim komutu cozulene kadar bekliyor. Aday imaji hostta mevcut, ancak aday servisleri su anda down.

## 2026-08-03 - Aday compose referans uyumsuzlugu

- `GAP`: Aday compose dosyasi silinmis eski `d724/esm:candidate-dd198c0da` imajini referansliyor; f00 imaji da daha sonra temizlendiginden temiz lifecycle baslatilamadi. Kismi aday container/volume'lari kaldirildi. Aktif `d724-esm-*` servisleri saglikli ve degistirilmedi.
- `NEXT`: Yerel son committen yeni aday build context/compose olustur, aday imajini build et, sonra quick setup + 18 paket regression kos.

## 2026-08-03 - Aday yeniden ayakta, DB bootstrap eksigi

- `VERIFIED_BY_CURRENT_TEST`: Aday compose f00 imajina uyarlanarak `127.0.0.1:18080` portunda yeniden baslatildi; web, db, redis healthy, daemon Up. Aktif `d724-esm-*` servisleri degistirilmedi.
- `GAP`: Temiz MariaDB volume'unda `careoncloud_esm` kullanicisi/schemas bootstrap edilmedigi icin unit test DB baglantisi `Access denied` ile duruyor. Quick setup + package install sonraki aday adimidir.

## 2026-08-03 - Temiz aday bootstrap ve TicketAudit ayrisik failure

- `VERIFIED_BY_CURRENT_TEST`: Aday DB `quick_setup.pl` ile bootstrap edildi; 18 paket eski aday kaynak kopyasindan build/install edildi ve ilk 6 paket (Foundation, TenantGuard, Audit, TenantDirectory, Catalog, Request) PASS verdi.
- `RISK`: TicketAudit grubunda `TicketAudit.t` kaynak derleme hatasi (`Test2::Tools::Compare::is` eksik arguman, no plan) ve `TicketAuditStatus.t` 5 failure goruldu. Bu aday kaynak kopyasi yerel son marka/TicketAudit commitlerini icermiyor; sonucu guncel kod regresyonu olarak genelleme.
- `NEXT`: Yerel son committen aday package tar'i/build context'i aktar; eski kaynak kopyasini kullanmadan OPM kur ve TicketAudit grubunu yeniden kos.

## 2026-08-03 - Guncel TicketAudit aday runtime kabulü

- `VERIFIED_BY_CURRENT_TEST`: Kullanici tarafindan `/tmp/careoncloud-ticketaudit.tar` olarak aktarilan yerel son TicketAudit paketi aday web container'inda build/install edildi. Quick-setup legacy ticket `ID=1` temizlendikten sonra `D724TicketAudit` 4 dosya / 227 test ile `All tests successful`, `Result: PASS` verdi. `TicketAudit.t`, `TicketAuditStatus.t`, `TicketPolicy.t` ve `SearchPolicy.t` dahil edildi.
- `SCOPE`: Bu kanit aday f00 image + temiz aday MariaDB/Redis/application volume'unda alindi; aktif `d724-esm-*` ve Yetka degistirilmedi. Beklenen deny-policy loglari assertion kanitidir.

## 2026-08-03 - Aday 18 paket regresyon matrisi

- `VERIFIED_BY_CURRENT_TEST`: Foundation 16, TenantGuard 192, Audit 29, TenantDirectory 57, Catalog 89, Request 62, TicketAudit 227, Problem 28, CMDB 61, Change 25, Commitment 121, Webhook 61, Identity 71, SCIM 60, Assist 19 ve Observability 37 test PASS verdi.
- `RISK`: D724API 160 testte 2 failure (API.t fixture ticket scope eksigi); D724Reporting 73 testte 15 failure (Reporting v0.4.1 bos selected-column SQL uretiyor). Bunlar adayda kurulu kaynak surumlerinin mevcut kanitidir; yerel son tum paket commitleri adaya aktarilmis degildir.

## 2026-08-03 - P0 aday tam regresyon kabulü

- `VERIFIED_BY_CURRENT_TEST`: Yerel API + Reporting paket arşivi adayda kuruldu; ardından 18 paket regresyon scripti tam olarak `exit code 0` ile tamamlandi. API 160 ve Reporting 73 test dahil tum paketler `All tests successful` verdi. Beklenen deny-policy/FK loglari negatif assertion kanitidir.
- `SCOPE`: Aday f00 imaji, izole `127.0.0.1:18080` portu ve aday MariaDB/Redis/application volume'lari; aktif `d724-esm-*` ve Yetka degistirilmedi. Quick-setup legacy ticket temizligi test oncesi uygulandi.

## Bilerek ertelenen

- Test yayını Cloudflare Tunnel ve TLS ile açılmıştır; üretim öncesinde Cloudflare Access/WAF, origin sertleştirmesi, kalıcı secret yönetimi ve bağımsız güvenlik testi tamamlanmalıdır.
- GitHub Actions workflow'u depoda bulunur ancak fork icin Actions calistirma politikasi ayrica etkinlestirilmelidir.
- Katalog, cekirdek OTOBO ticket yazimlari, TicketSearch, Generic Interface ortak ticket get/history/update erisimi, D724 commitment/webhook daemon isleri, operasyon rapor/export'u, D724 cache ve aktif Elasticsearch ticket aramasi tenant scope'a baglidir. Generic Interface operasyon-bazli role/action matrisi aciktir.
- OTOBO paket şema çeviricisinin çok sütunlu foreign key sınırlaması, idempotent post-install/upgrade sertleştiricisi ve health doğrulamasıyla giderilmiştir.
- OTOBO paket upgrade'inden sonra uzun omurlu Perl web worker'lari yeniden baslatilmalidir; aksi halde ayni anda eski ve yeni adapter kodu calisabilir. Test deploy runbook'u artik `web` ve `daemon` restart + HTTP health kontrolunu zorunlu kabul eder.
- Request lifecycle, D724 katalog, tenant-directory, kapsanan OTOBO ticket/MIME article, Chat lifecycle, Generic Interface `TicketUpdate` ve core pending-check scheduler mutasyonlari transaction-atomic audit kanitina sahiptir. Generic Interface `TicketCreate` source-level transaction ve rollback regresyonuna sahiptir ancak current candidate MariaDB kabulü bekler. GenericAgent ve diger scheduler/daemon yolları, non-MIME article backend'leri, harici eklenti/dogrudan DB yazimlari ile index/storage gibi cross-system side effect'ler ayni completeness garantisinin disindadir.

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
# 2026-08-03 Current candidate source synchronization

- VERIFIED_BY_CURRENT_TEST: all 18 current package sources were transferred, rebuilt and installed in the isolated candidate; the 18-package regression exited with code 0, including API (160) and Reporting (73) tests.
- SCOPE: only the careoncloud-candidate-f00f22e7b compose project was changed; active d724-esm services, volumes and Yetka data were untouched.
- RISK: candidate image remains d724/esm:candidate-f00f22e7b; a fresh image build, SBOM and signed release are still open.
# 2026-08-03 UI/URL P1 gözlem kaydı

- `RISK`: Aday ekran görüntüsünde kullanıcıya görünen adres yolu `/otobo/index.pl?Action=AgentD724Operations`; CareOnCloud kullanıcı yüzünde `/careoncloud` canonical yolu henüz doğrulanmış değil.
- `RISK`: Aynı Türkçe agent oturumunda `Report scope`, `Please select a time zone...` ve bazı menü/alan metinleri İngilizce kalırken diğer menüler Türkçe görünüyor. Bu, dil paketinin eksik olmasından veya aktif dil/cache kapsamının tutarsız olmasından kaynaklanabilir; paket kaynaklarında ilgili çeviri anahtarları ayrıca kabul testine alınmalı.
- `NEXT`: URL rewrite/canonical path'i adayda izole doğrula; Reporting ve ortak agent chrome için TR/EN metin envanteri çıkar, eksik anahtarları güncelle ve iki dilde ekran kabulü çalıştır. Üretim origin'inde değişiklik yapılmayacak.
- `VERIFIED_BY_CURRENT_TEST`: Aday kaynak `Kernel/Config/Files/ZZZAAuto.pm` içinde `ScriptAlias = careoncloud/` bulunuyor. Canlı `https://esm.arcak.net/otobo/index.pl?Action=AgentD724Operations` HTTP 200 dönerken `/careoncloud/index.pl` HTTP 404; canlı yanıtında `Set-Cookie: OTOBOBrowserHasCookie` ve `x-powered-by: OTOBO 11.1.x` mevcut. Bu, aday kodundan bağımsız canlı deployment/cutover gap'idir.
- `DONE_AND_VERIFIED`: Upstream `/otobo` örneklerini değiştirmeden `scripts/apache2-httpd-careoncloud-plack-proxy.include.conf` canonical `/careoncloud/` ve `/careoncloud-web/` route'ları için eklendi. `development/d724/Test-CareOnCloudProxyConfig.ps1` statik route sözleşmesini ve legacy route sızıntısını kontrol ediyor; test `PASS`.
- `RISK`: Bu dosya henüz canlı vhost'a bağlanmadı. Aday portta ayrı vhost, login/cookie/static asset ve geri dönüş testi tamamlanmadan enable edilmemelidir.

## 2026-08-03 - Request menusu Türkçe çeviri kapsamı

- `DONE_AND_VERIFIED`: D724Request paketinde eksik olan `tr_D724Request.pm` eklendi; `D724 Requests` ve temel request workbench terimleri Türkçeleştirildi ve SOPM filelist'e alındı.
- `VERIFIED_BY_CURRENT_TEST`: Adayda çeviri dosyası Perl syntax kontrolünden geçti; D724Request 4 dosya / 62 test ile `PASS` oldu.
- `RISK`: Aday container'a tek dosya syntax doğrulaması için aktarıldı; kalıcı paket güncellemesi bir sonraki 18 paket build/install döngüsünde yapılmalı. Canlı cluster değiştirilmedi.

## 2026-08-03 - Agent menüleri Türkçe çeviri kapsamı

- `DONE_AND_VERIFIED`: D724Assist, D724CMDB ve D724Change paketlerine Agent Assistant, Service Portfolio ve Change Enablement menü/başlık çevirileri eklendi ve her SOPM filelist'ine kaydedildi.
- `VERIFIED_BY_CURRENT_TEST`: Üç yeni dil dosyası aday container'ında Perl syntax kontrolünden geçti; paket XML manifestleri parse edildi. Assist 19, CMDB 61 ve Change 25 test ile `PASS` oldu.
- `RISK`: Bu tur paket kaynakları Git'e alındı; aday runtime'da kalıcı görünürlük için tüm 18 paket build/install döngüsü ve dil seçiciyle iki ayrı HTTP kabulü hâlâ gereklidir. Canlı cluster değiştirilmedi.

## 2026-08-03 - Commitment ve Problem Türkçe menüleri

- `DONE_AND_VERIFIED`: D724Commitment ve D724Problem için Türkçe dil dosyaları eklendi; taahhüt/uyarı/ihlal ve problem yönetimi menü terimleri çevrildi, SOPM filelist'lerine kaydedildi.
- `VERIFIED_BY_CURRENT_TEST`: Manifest XML parse edildi, iki dil dosyası aday container'ında syntax kontrolünden geçti. Commitment 121 ve Problem 28 test ile `PASS` oldu.
- `RISK`: Aday web worker'larında kalıcı dil cache yenilemesi ve tüm paketlerin birleşik yeniden kurulumu hâlâ açık; canlı cluster değiştirilmedi.

## 2026-08-03 - Güncel i18n paket regresyonu

- `VERIFIED_BY_CURRENT_TEST`: Güncel HEAD paket arşivi adayda 18 paket build/install döngüsünden geçirildi ve tam regresyon `exit code 0` ile tamamlandı. Yeni i18n paketleri dahil edildi; beklenen deny-policy/FK logları negatif test assertion'larıdır.
- `DONE_AND_VERIFIED`: Türkçe `Agent Assistant` karşılığı ürün terminolojisi kararıyla `Destek Asistanı` olarak standardize edildi (commit `f90ba2d44`).
- `RISK`: Bu son tek satır terminoloji değişikliği regresyon tamamlandıktan sonra yapıldı; kalıcı aday görünürlüğü için `careoncloud-all-packages-latest-i18n.tar` arşivinin yeniden kurulması/aktarılması ve i18n HTTP kabulü gerekir. Canlı cluster değiştirilmedi.
- `VERIFIED_BY_CURRENT_TEST`: `careoncloud-all-packages-latest-i18n.tar` aktarılmış, 18 paketin tamamı adayda yeniden build/install edilmiş ve tam regresyon tekrar `exit code 0` ile sonuçlanmıştır. Aday web/daemon/db/redis servisleri ayakta kalmış, aktif `d724-esm-*` servislerine dokunulmamıştır.
- `VERIFIED_BY_CURRENT_TEST`: Aday `127.0.0.1:18080/careoncloud/index.pl` HTTP `200` döndürüyor; `X-CareOnCloud-Login`, `X-Powered-By: CareOnCloud ESM 11.1.x` ve `CareOnCloudBrowserHasCookie` canonical `/careoncloud/` yolu ile geliyor. Yanıtta kalan OTOBO/OTRS satırları upstream yasal telif yorumlarıdır; kullanıcı yüzü başlık/logo ve URL'ler CareOnCloud'dur.
- `RISK`: Bu HTTP kanıtı anonim login yüzeyidir; authenticated Türkçe/İngilizce agent ekranı ve canlı Cloudflare cutover kabulü hâlâ yapılmadı.
- `VERIFIED_BY_CURRENT_TEST`: Güncel HEAD `332b355c6c43cac0c98d28928c704d95882717fb` için temiz detached worktree'de SourceArtifact manifest, güncel Git commit ve archive SHA-256 sözleşmesi tekrar `PASS` oldu.
- `VERIFIED_BY_CURRENT_TEST`: Aday web container'ında güncel `tr_D724Assist`, `tr_D724CMDB`, `tr_D724Change`, `tr_D724Commitment`, `tr_D724Problem` ve `tr_D724Request` dosyalarının tamamı mevcut; aday web/db/redis sağlıklı, daemon `Up`.
- `VERIFIED_BY_CURRENT_TEST`: Güncel checkout'ta CareOnCloud brand contract (16 required, 15 forbidden path, 18 package) ve canonical proxy contract testleri tekrar `PASS` oldu.

## 2026-08-03 - CareOnCloud imzalı release workflow taslağı

- `DONE_AND_VERIFIED`: Upstream OTOBO release workflow'una dokunmadan `.github/workflows/careoncloud-release.yml` eklendi. Manuel veya `careoncloud-v*` tag tetiklemesiyle `careoncloud.web.dockerfile` içindeki `careoncloud-web` target'ını GHCR'a immutable tag ile iter, CycloneDX SBOM artifact'i üretir ve GitHub OIDC üzerinden Cosign keyless imza atar.
- `RISK`: Workflow GitHub Actions üzerinde henüz çalıştırılmadı; GHCR repository/package izinleri ve release tag politikası ayrıca doğrulanmalı. Bu workflow canlı cutover yapmaz.
- `VERIFIED_BY_CURRENT_TEST`: `development/d724/Test-CareOnCloudReleaseWorkflow.ps1` workflow'un CareOnCloud Dockerfile/target, GHCR, SBOM, Cosign ve OIDC izinlerini içerdiğini; upstream OTOBO image hedefi içermediğini doğruluyor.

## 2026-08-03 - Türkçe saat dilimi uyarısı düzeltmesi

- `DONE_AND_VERIFIED`: `Kernel/Language/tr.pm` içindeki boş saat dilimi uyarısı Türkçe çeviriyle dolduruldu.
- `VERIFIED_BY_CURRENT_TEST`: Güncel dosya aday web container'ında Perl syntax kontrolünden geçti; D724Reporting 4 dosya / 73 test ile `PASS` oldu.
- `RISK`: `/otobo/` canonical URL ve diğer karışık dil metinleri ayrı aday kabul işidir; bu değişiklik yalnızca çekirdek uyarı çevirisini düzeltir.
## 2026-08-03 - P1 clean lifecycle and image security gate

- `VERIFIED_BY_CURRENT_TEST`: GitHub Actions run `30817232194` for commit `26ba933b3` passed the complete D724 foundation workflow, including clean package lifecycle, 18-package regression, source artifact, SBOM, and repository/image vulnerability gates.
- `DONE_AND_VERIFIED`: The image scan initially reported ten HIGH `linux-libc-dev` findings; `careoncloud.web.dockerfile` now explicitly installs the patched package and the rebuilt image scan passed.
- `DONE_AND_VERIFIED`: Generic Interface TicketCreate and GenericAgent tenant fixtures are isolated and audit-aware; their clean-container acceptance completed successfully.
- `RISK`: Authenticated Turkish/English UI acceptance, the actual signed release tag workflow, and production cutover remain intentionally open. Production services were not changed.

## 2026-08-03 - Authenticated candidate UI acceptance

- `DONE_AND_VERIFIED`: Temporary candidate-only agent session successfully selected `Türkçe - Turkish` through the real preferences widget; after save, authenticated navigation displayed `Destek Asistanı`, `Hizmet Portföyü`, `Değişiklik Yönetimi`, `Problem Yönetimi` and `Müşteriler`.
- `DONE_AND_VERIFIED`: The same candidate session selected `Europe/Istanbul`; the time-zone warning disappeared after save. All observed authenticated links remained under `/careoncloud/index.pl`.
- `DONE_AND_VERIFIED`: Returning the candidate session to English retained the canonical `/careoncloud/` routes and English navigation, proving both selectable UI languages without touching production services.
- `RISK`: This is candidate-only browser evidence using a temporary acceptance user; signed release-tag execution, live cutover/rollback and production acceptance remain open.

## 2026-08-03 - Candidate release workflow execution

- `VERIFIED_BY_CURRENT_TEST`: Release workflow contract test passed and candidate tag `careoncloud-v0.0.0-candidate.817d13ebb` reached GitHub Actions run `30820150916`; checkout, immutable-tag validation and GHCR authentication completed successfully.
- `RISK`: The remote Docker build produced no streamed logs and remained in the build step; the candidate-only run was canceled after 6m31s to avoid unbounded runner consumption. SBOM and Cosign steps therefore did not execute. No production image or service was changed.
- `NEXT`: Optimize or prebuild the release image path (the current Docker context is approximately 352 MB and performs the full CPAN deployment) before rerunning the candidate tag workflow; retain the failed/canceled run as evidence rather than claiming a signed release.

## 2026-08-03 - Release build cache hardening

- `DONE_AND_VERIFIED`: `.github/workflows/careoncloud-release.yml` now uses a dedicated GitHub Actions cache scope for the CareOnCloud web image (`cache-from`/`cache-to`, `mode=max`) so subsequent immutable candidate builds can reuse the expensive CPAN and image layers without changing the image contents or signing policy.
- `VERIFIED_BY_CURRENT_TEST`: `Test-CareOnCloudReleaseWorkflow.ps1` passed after the cache change; commit `78e745b1e` was pushed to `codex/esm-foundation`.
- `RISK`: A fresh candidate run is still required to prove the cache-backed build reaches SBOM and Cosign; the prior run was canceled before those steps.

## 2026-08-03 - Release cache driver correction

- `VERIFIED_BY_CURRENT_TEST`: Candidate run `30820904874` failed immediately with the authoritative BuildKit error `Cache export is not supported for the docker driver`; no image, SBOM or signature was produced.
- `DONE_AND_VERIFIED`: The release workflow now provisions `docker/setup-buildx-action@v3` before using the GitHub Actions cache backend, and the workflow contract test covers both the builder and cache settings. Commit `5e8a7a5af` was pushed.
- `RISK`: A new candidate tag run is required to prove the corrected builder reaches image push, SBOM upload and Cosign signing.

## 2026-08-03 - Candidate Buildx run observation

- `VERIFIED_BY_CURRENT_TEST`: Candidate run `30821129445` successfully initialized the cache-capable Buildx builder and reached the image build step; the workflow API emitted no build progress and remained unchanged, so the run was canceled after 3m22s. SBOM and Cosign were not reached.
- `RISK`: This is an infrastructure/build-duration observation, not a release success. The full CPAN deployment layer needs a separately observable/prewarmed build path before the signed release gate can be claimed.

## 2026-08-03 - Release build observability hardening

- `DONE_AND_VERIFIED`: Release workflow upgraded to Buildx/setup actions v4/v7, enables `progress: plain` and `pull: true`, and passes an explicit non-local `DOCKER_TAG` so the Dockerfile deterministically uses the locked deployment snapshot.
- `VERIFIED_BY_CURRENT_TEST`: Release workflow contract test passed after the change; commit `8b61ed9f9` was pushed.
- `RISK`: A fresh candidate tag run is still required to confirm observable CPAN progress and reach SBOM/Cosign; previous runs were canceled before those steps.

## 2026-08-03 - Build action input correction

- `VERIFIED_BY_CURRENT_TEST`: Candidate run `30821523907` reached Buildx but reported the authoritative action warning `Unexpected input(s) 'progress'`; the run was canceled before image build. No SBOM or signature was produced.
- `DONE_AND_VERIFIED`: Removed the unsupported `progress` input and its contract assertion; the release workflow contract test passed. Commit `5e31e8150` was pushed.
- `RISK`: A fresh candidate tag run remains necessary to validate the corrected action invocation and signed release path.

## 2026-08-03 - Corrected release action run

- `VERIFIED_BY_CURRENT_TEST`: Candidate run `30821704656` passed checkout, tag resolution, GHCR login and Buildx setup. It then remained in the image build step without progress or API timestamp updates and was canceled after 1m56s; SBOM/Cosign were not reached.
- `RISK`: Repeated no-progress behavior is now isolated to the remote Docker build stage, not action input validation. No production image/service was changed and no signed release is claimed.

## 2026-08-03 - Static P1/P2 contract regression sweep

- `VERIFIED_BY_CURRENT_TEST`: On commit `ec5f168aa`, CareOnCloud brand contract passed (16 required paths, 15 forbidden paths, 18 packages), critical customer/agent language contract passed for 2 journeys, canonical proxy contract passed, and release workflow contract passed.
- `RISK`: These deterministic source contracts do not substitute for the still-open remote image build, SBOM upload, Cosign signature, or live cutover/rollback evidence.

## 2026-08-04 - Release build "stall" root cause: premature cancellation, not a build defect

- `DONE_AND_VERIFIED`: The reported build stall was a measurement error, not a defect. The GitHub Actions run-level `updatedAt` field does not tick while a single step runs long; it only updates on step transitions. `gh run view --log` likewise returns nothing for an in-progress run. Both were read as "no progress" and every run was canceled below the image's normal ~7 minute build time.
- `VERIFIED_BY_CURRENT_TEST`: The last log lines before each cancellation show healthy progress. Run `30820150916` — the first run, before any workflow change — had already finished building and was at `#27 pushing layer 1.03GB / 1.43GB` when it was canceled at 6m16s. Run `30821704656` was at `#16 25.97 Successfully installed DBI-1.651` when canceled at 1m29s.
- `VERIFIED_BY_CURRENT_TEST`: Independent corroboration from the same day and runner class: in foundation run `30817232194`, step `Accept clean D724 package lifecycle` ran 8m15s, built `careoncloud.web.dockerfile` successfully, and the following step scanned the built image and passed. The Dockerfile was never failing on GitHub runners.
- `RISK`: `cache-to` exports only at the end of a build, so every cancellation also prevented the cache from ever being written. Each rerun therefore started cold and looked equally slow, which reinforced the false diagnosis. The added cache was not ineffective; it was never given the chance to persist.

## 2026-08-04 - Signed release chain completed end to end

- `VERIFIED_BY_CURRENT_TEST`: Run `30824056768` on commit `e82d348c1` completed the full chain with `conclusion: success` in 9m55s, with the workflow left **unmodified** and dispatched via `workflow_dispatch` so the experiment would not be confounded. Build and push 7m04s, SBOM 1m57s, SBOM upload 2s, Cosign install 1s, keyless OIDC signature 4s.
- `VERIFIED_BY_CURRENT_TEST`: Image digest `sha256:e6075fb47fc43e085c703822745a9356f402499ea6dd99571a0df058a8239255` pushed to `ghcr.io/akinarcak/otobo/careoncloud:v0.0.0-probe.e82d348c1`. SBOM artifact `careoncloud-sbom-v0.0.0-probe.e82d348c1` is 1,287,359 bytes with `expired=false`. Cosign v2.5.0 keyless OIDC recorded `tlog entry created with index: 2335222741` and pushed the signature to GHCR.
- `SCOPE`: Candidate-only `workflow_dispatch` probe tags. Production services, live cutover, `d724-esm-*` containers/volumes and Yetka data were not touched. Only `v0.0.0-probe*` images were pushed to GHCR.
- `RISK`: This proves the release mechanism, not a release. An actual `careoncloud-v*` tag, live cutover and rollback rehearsal remain open.

## 2026-08-04 - DOCKER_TAG build-arg measured as a CPAN cache invalidator

- `VERIFIED_BY_CURRENT_TEST`: Controlled experiment on the same commit `e82d348c1` with the same workflow, differing only in image tag. Run `30824056768` build+push 7m04s; run `30882609007` build+push 4m45s with base layers 1/7 through 6/7 reported `CACHED` and base layer 7/7 (`carton install`) reinstalling 213 CPAN distributions in 211.9s. The cache hit stopped precisely at the layer that consumes the `DOCKER_TAG` ARG.
- `DONE_AND_VERIFIED`: The `DOCKER_TAG=careoncloud-<tag>` build-arg was removed from `.github/workflows/careoncloud-release.yml` in commit `41fc6a9b1`. It provided no function: the Dockerfile default `unspecified` already fails the `local-*` test and selects the locked `carton install --deployment` path. The version label it appears to feed is out of scope in the `careoncloud-web` stage regardless, because ARGs do not cross a `FROM` boundary and that stage never redeclares it.
- `VERIFIED_BY_CURRENT_TEST`: `Test-CareOnCloudReleaseWorkflow.ps1` passed after the change and now carries a regression guard that fails if a `DOCKER_TAG=` build-arg is reintroduced.
- `DONE_AND_VERIFIED`: `docs/esm/NOTES-FOR-CODEX.md` records the root cause, the measurement error that produced it, and the operating rules to avoid repeating it.

## 2026-08-04 - CareOnCloud web image version label

- `DONE_AND_VERIFIED`: Added `ARG DOCKER_TAG=unspecified` inside the `careoncloud-web` stage immediately before its OCI metadata labels, so `org.opencontainers.image.version` is populated instead of empty across web image builds. The Kerberos stage already had the equivalent declaration.
- `VERIFIED_BY_CURRENT_TEST`: CareOnCloud brand and release workflow contract tests passed; commit `57b81bb99` was pushed.

## 2026-08-04 - CycloneDX SBOM naming alignment

- `DONE_AND_VERIFIED`: Renamed the release workflow step from `Generate SPDX SBOM` to `Generate CycloneDX SBOM`; the action continues to emit `format: cyclonedx-json` and the artifact contents are unchanged.
- `VERIFIED_BY_CURRENT_TEST`: Release workflow contract test passed after the naming correction; commit `02a8de71c` was pushed.

## 2026-08-04 - GitHub Actions cache measurement

- `VERIFIED_BY_CURRENT_TEST`: GitHub cache API reported 44 active caches totaling 1.319 GiB (`1,415,847,893` bytes). BuildKit-related entries accounted for 37 caches / 0.952 GiB, with entries from `2026-08-03T14:49:39Z` through `2026-08-04T06:19:02Z`.
- `DONE_AND_VERIFIED`: The current cache footprint is well below the repository's 10 GiB Actions cache limit; no eviction or pressure signal was observed, so no `mode=min` or registry-cache migration is justified by current evidence.
- `RISK`: GitHub cache eviction is policy-driven and can change with future workflow runs; remeasure before a release if the active footprint approaches the limit.

## 2026-08-04 - Cache fix verified: tag changes no longer rebuild the CPAN layer

- `VERIFIED_BY_CURRENT_TEST`: After commit `41fc6a9b1` removed the `DOCKER_TAG` build-arg, run `30883159985` (tag `probe3`) repopulated the cache under the new key in 4m50s, and run `30883550612` (tag `probe4`) completed its build and push in **9 seconds** with `#11 [base 7/7] RUN` reported `CACHED` and zero `Successfully installed` lines. `carton install` did not execute at all.
- `VERIFIED_BY_CURRENT_TEST`: The decisive condition is that `probe4` differs from `probe3`. A differing tag previously invalidated the CPAN layer on its own; it no longer does. Build and push fell from 7m04s cold to 9s cached, and the complete chain from 9m55s to 1m32s.
- `VERIFIED_BY_CURRENT_TEST`: Run `30883550612` still finished the full chain with `conclusion: success` — build/push, SBOM generation, SBOM artifact upload and Cosign keyless OIDC signing. The cache optimisation did not weaken the signed release path.
- `SCOPE`: Candidate-only `workflow_dispatch` probe tags. Production services, live cutover, `d724-esm-*` containers/volumes and Yetka data were not touched.
- `RISK`: Still open and not claimed as done: an actual `careoncloud-v*` signed release tag, live Cloudflare cutover with rollback rehearsal, and production acceptance.
