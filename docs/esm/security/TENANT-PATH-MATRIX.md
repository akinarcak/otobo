# P0.2 Tenant Yol ve Negatif Test Matrisi

Durum: `PARTIAL`. Bu belge, CareOnCloud kodunda tenant sinirini kullanan yollarin mevcut kaynak ve test kanitini toplar. Bir satirin testi olmasi, tum OTOBO yuzeyinin tenant-izole oldugu anlamina gelmez.

## Sinir sozlesmesi

- Tenant karari `D724TenantGuard` tarafindan resource tenant'i ile verilir; request parametresi veya OTOBO grup/queue yetkisi tek basina sinir degildir.
- Diger tenant'taki kaynagin varligini gizlemesi gereken HTTP/API yollarinda `NOT_FOUND` tercih edilir; yetkili bir kaynaga yasak eylem `FORBIDDEN` olur.
- Daemon ve scheduler mutasyonlari aktif tenant ve `automation:<job>` policy context'i olmadan calisamaz.

## Mevcut yol envanteri

| Yuzey | Enforcement noktasi | Negatif kanit | Kanit durumu |
|---|---|---|---|
| Merkezi policy | `D724TenantGuard::DecisionGet` / `ScopeGet` | Diger tenant, case-sensitive tenant ID ve kapali platform-admin bypass'i reddedilir | `VERIFIED_BY_CURRENT_TEST`: `TenantGuard.t`, `TenantGuardCheck.t` |
| Tenant directory | `D724TenantDirectory` membership/context | Diger tenant admin'iyle directory audit export reddedilir; role bindings tenant bazlidir | `VERIFIED_BY_CURRENT_TEST`: `TenantDirectory.t` |
| Katalog | `D724Catalog`, agent/customer frontend adapter'lari | Cross-tenant service/parent/schema/audit erisimi reddedilir; DB foreign-key siniri gecersiz offering bagini reddeder | `VERIFIED_BY_CURRENT_TEST`: `Catalog.t`, `CatalogConstraint.t`, `CatalogAgentContext.t` |
| Request | `D724Request`, customer/agent adapter'lari | Yabanci catalog item `NOT_FOUND`; diger tenant agent request listesi `FORBIDDEN` | `VERIFIED_BY_CURRENT_TEST`: `Request.t`, `RequestFrontend.t` |
| API bearer ve ticket | `D724API::APIAuth`, `D724API::API` ve public API | Token baska tenant icin `CROSS_TENANT`; yabanci ticket `NOT_FOUND`; yabanci client lookup gizlenir | `VERIFIED_BY_CURRENT_TEST`: `APIAuth.t`, `API.t` |
| Core ticket search/write | `D724TicketAudit::TicketPolicy` ve core ticket wrappers | CustomerID raw bypass'i reddedilir; agent yalniz kendi ticket scope sonucunu gorur | `VERIFIED_BY_CURRENT_TEST`: `TicketPolicy.t`; aday HTTP kabulune ait kanit `Accept-TicketPolicy.pl` |
| Generic Interface ticket update | `D724TicketAudit::D724AuditCustom` ve GI request wrapper | Ortak ticket update yolu transaction/scope audit sozlesmesine baglidir | `VERIFIED_BY_CURRENT_TEST`: `TicketAudit.t`; aday gercek HTTP kabul `Accept-GenericInterfaceTicketUpdate.pl` |
| Arama | `D724TicketAudit::SearchPolicy` ve Elasticsearch final invoker | Explicit cross-tenant filter bos intersection ile reddedilir; yabanci hit donmez | `VERIFIED_BY_CURRENT_TEST`: `SearchPolicy.t`; aday runtime kabul `Accept-ElasticsearchRuntime.pl` |
| Cache | `D724TenantGuard::TenantCache` | Baska subject kendi olmayan tenant namespace'ini okuyamaz | `VERIFIED_BY_CURRENT_TEST`: `TenantCache.t`, `Accept-TenantCache.pl` |
| Reporting/export | `D724Reporting` | Cross-tenant export `FORBIDDEN`; export aggregate-only ve PII-minimize edilir | `VERIFIED_BY_CURRENT_TEST`: Reporting testleri; aday kabul `Accept-Reporting.pl` |
| Webhook | `D724Webhook` subscription repository/public API | Requester create yasagi ve yabanci tenant subscription list leak denetimi | `VERIFIED_BY_CURRENT_TEST`: `Webhook.t`, `WebhookStatus.t`; aday kabul `Accept-WebhookSubscription.pl` |
| Daemon/scheduler | TenantGuard automation context, Commitment/Webhook ve TicketAudit pending wrapper | Tenant olmadan automation reddi; pending-check her aktif tenant icin calisir | `VERIFIED_BY_CURRENT_TEST`: `TenantGuardAutomation.t`; aday SchedulerTaskWorker kabul `Accept-SchedulerTicketPendingCheck.pl` |

## Acik kapsama ve kabul sinirlari

| Alan | Durum | Gerekli sonraki kanit |
|---|---|---|
| Native OTOBO agent/customer ekranlarindaki tum ticket read/query yollari | `PARTIAL` | Kimligi farkli iki tenant ile authenticated HTTP negative matrix; list, detail, history, attachment ve search |
| Core Generic Interface operasyonlarinin tamami | `PARTIAL` | TicketCreate/get/history ve her mutator icin tenant negatif HTTP kabul |
| GenericAgent, diger daemon job'lari ve harici yan etkiler | `PARTIAL` | Job bazli tenant context, mutasyon ve cross-tenant negatif kabul |
| Dogrudan veritabani yazimi | `OUT_OF_SCOPE` | Uygulama policy sinirini bypass eder; deployment DB erisimi ayri operasyonel sertlestirme/pentest kapsamidir |
| Platform-admin acil durum bypass'i | `PARTIAL` | Iki anahtarli enablement, audit ve runbook ile negatif/pozitif kabul |

Bu matris sadece mevcut testlerin kapsamini raporlar. Pilot veya production izolasyon iddiasi icin acik satirlarin tamamlanmasi gerekir.
