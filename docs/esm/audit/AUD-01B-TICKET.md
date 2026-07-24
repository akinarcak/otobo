# AUD-01b OTOBO Ticket Core Atomic Audit

Durum: cekirdek kapsam tamamlandi (`2026-07-24`).

## Kapsam

`D724TicketAudit 0.4.1`, OTOBO'nun resmi `Ticket::CustomModule` extension mekanizmasini kullanir; upstream `Kernel::System::Ticket` dosyasi degistirilmez. Su yazimlar kapsanir:

- `ticket.created`
- `ticket.title.updated`
- `ticket.queue.updated`
- `ticket.customer.updated`
- `ticket.lock.updated`
- `ticket.state.updated`
- `ticket.owner.updated`
- `ticket.responsible.updated`
- `ticket.priority.updated`
- `ticket.article.created` (Email/Internal/Phone ortak MIMEBase yolu)

Article body audit details'e kopyalanmaz. Subject, sender type, customer visibility ve storage tipi gibi sinirli metadata kaydedilir. Uzun mutation state degerleri 50 karakterlik state kolonuna ham yazilmaz; deterministik SHA-256 token kullanilir ve tam deger normalize details alaninda kalir.

## Tenant ve transaction garantisi

Her ticket `d724_ticket_scope` tablosunda degismez tenant kimligi ve monoton mutation version'i alir. Yeni ticket aktif D724 tenant'a eslesen `CustomerID/CustomerNo` olmadan yaratilamaz. Customer user ayni tenant icinde degisebilir; CustomerID'nin baska tenant'a tasinmasi reddedilir.

Ticket/domain yazimi, scope insert/version ve audit head/event append production `AutoCommit` cagrilarinda tek transaction'dir. Audit arizasinda ticket state, title/customer degisimi, article row/storage ve scope version rollback edilir. Rollback sonrasi OTOBO ticket/article cache'leri temizlenir.

MIME article atomikligi yalniz transaction destekli `ArticleStorageDB` icin etkinlestirilir. Harici filesystem/object storage, DB transaction'i ile atomik olmadigi icin fail-closed davranir; sonraki surumde transactional outbox/compensation adapter'i gerektirir.

## Upgrade ve legacy veri

- `Admin::D724::TicketScopeBackfill`: CustomerID'si aktif D724 tenant'a zaten eslesen unbound ticket'lari sinirli ve atomik batch ile scope'a alir; her kayit `ticket.scope.backfilled` olayi uretir.
- `Admin::D724::TicketScopeAssign`: tek bir uyumsuz legacy ticket icin acik tenant secimi ister. CustomerID farkliysa ayrica `--replace-customer-id` ve `--confirm` olmadan yazmaz; replacement+scope+audit ayni transaction'dir.
- `Admin::D724::TicketAuditStatus --json`: core/scoped/unbound/backfillable/invalid sayilarini ve en fazla 100 unbound kimligi raporlar. Her unbound ticket health sonucunu basarisiz yapar.

## Kanit

- Paket: 2 dosya / 67 test `PASS`.
- Tum D724 regresyonu: 25 dosya / 469 test `PASS`.
- Hata enjeksiyonu: state update, MIME article create, bulk backfill ve explicit CustomerID replacement audit kapaliyken rollback; retry tek version ve tek event uretir.
- Negatif izolasyon: tenantless create reddedilir; cross-tenant customer reassignment veriyi degistirmez.
- Demo kabul: `D724AUD20260724001`, TicketID `9`, state `open`, scope version `3`, actions `ticket.created`, `ticket.state.updated`, `ticket.article.created`, chain valid. Ikinci calisma `Created=0`.
- Legacy kabul: kurulum ticket'i ID `1` acik replacement onayiyla `d724-demo` tenant'ina atandi; `CoreTickets=2`, `Tickets=2`, `UnboundTickets=0`, `InvalidTenantTickets=0`.
- OPM SHA-256: `bbf753e8a16e1fc3669212c1a986f6e350ea063c7fe018f4645a2663fb77c141`.

## Acik kapsam

Ticket delete/merge/type/service/SLA/pending-time mutasyonlari, Chat backend article yazimlari, Generic Interface seviyesinde caller policy enforcement, ticket read/search tenant filtreleri ve harici article storage outbox/compensation adapter'i sonraki guvenlik kapilaridir.
