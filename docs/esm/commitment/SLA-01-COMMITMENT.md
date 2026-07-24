# SLA-01a Resolution Commitment Motoru

## Karar

`D724Commitment`, OTOBO'nun kanitlanmis `Kernel::System::DateTime` business-time hesaplarini kullanir. D724 tablolarinda tenant policy, request'e bagli immutable instance ve append-only lifecycle event'i tutulur. Boylece OTOBO takvim/tatil/timezone davranisi fork edilmez; urune ozel pause, warning, breach ve kanit semantigi eklenir.

## Veri ve durum modeli

- Policy: tenant-local key, calendar `0..9`, hedef saniye, warning yuzdesi, pause request status listesi ve optimistic version.
- Instance: request acildigi andaki policy snapshot'i, consumed business seconds, running/paused zamanlari, warning/due, `running|paused|warning|met|breached|cancelled` durumu.
- Event: actor, event time, onceki/yeni durum, tuketilen sure ve neden. Scheduler actor'u acikca `system:commitment-scheduler` olur.

Policy sonradan degisse bile acik request'in hedefi degismez. Ayni request/policy baslatmasi idempotent replay olur. Agent ve customer okumasi tenant ve request sahipligiyle sinirlanir.

## Calisma zamani ve scheduler

Destination ve elapsed hesaplari OTOBO calisma saatleri, tek-seferlik/yillik tatiller ve calendar timezone ayarlarini kullanir. Pause aninda tuketilen business seconds dondurulur; resume kalan sureyi yeni baslangictan hesaplayarak warning ve due zamanlarini kaydirir.

`D724CommitmentSweep` cron gorevi her dakika, en fazla tek paralel instance ile active commitment'lari degerlendirir. Warning ve breach gecisleri optimistic version kontroluyle yazilir; yarisan worker stale kaydi overwrite edemez.

## Request entegrasyonu

Katalog workflow'u `commitment.policy_key` ile tenant policy'yi secer. Request submission commitment'i otomatik baslatir. Onay bekleme pause kuralinda ise ilk durum `paused`; onay sonrasi `running`; rejection `cancelled`; son fulfillment gorevi `met` veya hedef asilmis ise `breached` sonucunu uretir.

## Dogrulama

- Sabit UTC fixture'lari ile warning, business-time due, gece/ertesi gun pause kaymasi, stale scheduler, met/breach ve cross-tenant denial test edilir.
- Altı D724 paketi 17 dosyada 275 testi birlikte gecirir.
- Oturumlu HTTP kabul testi demo talebini `paused -> running -> met` ve request'i `awaiting_approval -> in_fulfillment -> fulfilled` olarak tamamlamistir.

## Acik kapsam

`SLA-01b` response ve resolution icin birden fazla commitment, OLA/UC hedefleri, entitlement/priority secimi ve warning/breach sonrasinda notification/webhook/assignment escalation action'larini ekleyecektir. Bu nedenle genel `SLA-01` henuz tamamen kapanmis sayilmaz.
