# AUD-01 Audit Karari

Durum: `AUD-01a`, `AUD-01b-request`, `AUD-01b-catalog`, `AUD-01b-directory` ve `AUD-01b-ticket-core` tamamlandi (`2026-07-24`). `AUD-01b-core` acik.

## Amac ve guvenlik siniri

`D724Audit`, her tenant icin ayri ve monoton bir audit olayi zinciri tutar. Okuma, dogrulama ve export islemleri `D724TenantGuard` uzerinden `audit.read` karari almadan calismaz. Tenant kimligi export filtresinden veya tarayici girdisinden guvenilir kabul edilmez.

Bu katman kaydedilmis olaylarin sonradan sessizce degistirilmesini algilar. Request lifecycle, D724 katalog, tenant-directory ve kapsanan OTOBO ticket/MIME article adapter'lari uygulama mutasyonu ile audit append'ini ayni transaction'a alir. Diger domain adapter'lari ve DB-disinda immutable saklama henuz bu garantiyi tasimaz.

## Normalize olay kontrati

Her olay tenant, sequence, UUID, UTC event time, actor type/id, action, object type/id, correlation ID, from/to state, outcome, source IP hash, guvenli scalar details, previous hash, event hash ve opsiyonel migration-compatible dedupe key alanlarini tasir.

- Actor turleri: `customer`, `agent`, `system`, `integration`.
- Outcome: `success`, `denied`, `failure`.
- Details yalnizca sinirli sayida, sinirli uzunlukta scalar deger kabul eder.
- Source IP acik metin saklanmaz; tenant disi bir SysConfig salt'i ile SHA-256 pseudonym uretilir.
- Event hash, sirali JSON kanonigi uzerinden hesaplanir ve onceki event hash'ini kapsar.
- Tenant head satiri row lock ile sequence/hash ilerlemesini serialize eder.

## Idempotency ve zincir

Yeni olaylar zorunlu `DedupeKey` alir. MariaDB'deki `(tenant_id, dedupe_key)` unique constraint'i ve tenant head lock'i, ayni logical olay iki kez teslim edilirse yeni sequence olusturmak yerine ilk olay sonucunu dondurur. Eski 0.1.0 olaylarinda dedupe alani `NULL` kalir; dogrulama kanonigi geriye donuk olarak degismez.

`Verify`, sequence gap, previous-hash uyusmazligi, event-hash uyusmazligi ve head uyusmazligini ayri hata kodlariyla raporlar.

## Request lifecycle adapter'i

`D724Request 0.4.6` su olaylari senkron olarak uretir:

- `request.created`
- `request.approved` / `request.rejected`
- `request.first_response`
- `task.status_changed`
- `request.fulfilled`

Request creation replay'i ayni idempotency key ve payload ile orijinal request'i dondurur ve `request.created` olayini dedupe anahtariyla yeniden garanti eder. Approval ve task gecisleri optimistic version kontrolunu korur.

Customer submit, approval, first-response ve task update girisleri production `AutoCommit` baglantisinda transaction acar. Request/approval/task, commitment instance/event/outbox ve audit event/head yazimlarindan herhangi biri basarisizsa tum domain sonucu rollback edilir. Mevcut bir ust transaction varsa islem ona katilir ve commit sahipligini ele almaz.

## Okuma ve export

`List` en fazla 1000 olaylik tenant-kapsamli sayfa ve kararlı `NextSequence` cursor'i dondurur. Object filter tenant predicate'ini kaldiramaz. `ExportNDJSON`, her satirda bir normalize olay ve `application/x-ndjson` content type uretir; clear-text source IP export edilmez.

## Kanit

- Paketler: `D724Audit 0.2.0`, `D724TenantDirectory 0.2.1`, `D724Catalog 0.5.2`, `D724Request 0.4.6`, `D724Commitment 0.3.8`, `D724TicketAudit 0.6.1`.
- MariaDB migration kaniti: `d724_audit_dedupe(tenant_id, dedupe_key)` unique index'i mevcut.
- Audit + Request: 5 dosya / 80 test `PASS`.
- Tum D724 regresyonu: 25 dosya / 469 test `PASS`.
- Gercek HTTP akisi: `REQ-0000000086`, durum `fulfilled`, bes sirali ve farkli dedupe anahtarli lifecycle olayi.
- Ayni customer POST replay'i `REQ-0000000086` dondurdu; lifecycle event sayisi bes kaldi.
- Demo tenant zinciri katalog atomik kabul sonunda `Valid=1`, 20 event.
- Production-style transaction contract: domain failure sonrasinda mutation `0`, success sonrasinda durable row `1`.
- Gercek hata enjeksiyonu: create/approval/task audit hatalari tum bagli state'i rollback etti; ayni idempotency/optimistic version retry'lari basarili oldu ve `REQ-0000000102` fulfilled + uc commitment met durumuna geldi.
- Concurrent dedupe: iki proses ayni logical olayi yaristirdi; ikisi de success, biri replay, kalici event/head sayisi `1`.

## AUD-01b-core acik kapsam

- Kalan OTOBO ticket delete/merge/type/service/SLA/pending, Chat article, Generic Interface, commitment scheduler/escalation ve konfigurasyon mutasyonlarinda transaction veya transactional outbox completeness garantisi.
- Retention politikasi, legal hold, erasure istisnalari ve yetkili export UI/API.
- DB-disinda WORM/immutable sink, signing key rotation ve periyodik anchor.
- Audit delivery/completeness metrikleri, alarm ve reconciliation.
- Paket upgrade runbook'unda zorunlu web/daemon worker restart ve post-deploy verify.
