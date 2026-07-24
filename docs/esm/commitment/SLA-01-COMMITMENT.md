# SLA-01 Commitment Motoru

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

## Coklu hedef ve entitlement

Policy artik sirali `response`, `resolution` ve `ola` hedefleri tasir. Her hedef kendi baslangic/bitis sinyalini, takvim hedefini, warning oranini ve escalation action listesini snapshot olarak saklar. `request_created`, `request_approved`, `first_response` ve `request_fulfilled` sinyalleri hedefleri birbirinden bagimsiz baslatir veya kapatir.

Katalog workflow'u varsayilan policy'ye ek olarak sadece validate edilmis cevaplar uzerinde calisan sirali entitlement kurallari tanimlar. Eslesen kural tenant-local policy'yi secer; secim ve kural anahtari request snapshot'inda denetlenebilir bicimde kalir. Warning/breach action'lari benzersiz anahtarla outbox'a yazilir; ayni sweep ayni action'i ikinci kez kuyruklamaz.

## Escalation teslimi

`D724Commitment 0.3.0` dispatcher'i pending/retry kayitlarini atomik lease ile sahiplenir. Yarisan worker ayni action'i alamaz; gecici hata 60 saniyeden baslayan ussel backoff ile yeniden denenir ve maksimum deneme sonunda kayit `dead` olur. `attempt_count`, son hata, response code, islenme zamani ve delivery reference commitment kanitinda saklanir.

`notify_role`, alicilari sadece action tenant'indaki aktif directory rol uyeliklerinden cozer ve OTOBO email transport'una tenant/delivery basliklariyla kuyruklar. `assignment`, ayni tenant ve request'teki aktif fulfillment gorevini hedef gruba atar. `webhook`, policy icinde URL kabul etmez: adlandirilmis endpoint SysConfig/secret store'dan cozulur, yalnizca exact allow-list'teki HTTPS host'una gider ve payload HMAC-SHA256 ile imzalanir.

## Dogrulama

- Sabit UTC fixture'lari ile warning, business-time due, gece/ertesi gun pause kaymasi, stale scheduler, met/breach ve cross-tenant denial test edilir.
- Alti D724 paketi 17 dosyada 316 testi birlikte gecirir.
- Oturumlu HTTP kabul testi premium entitlement secilen `REQ-0000000042` talebinde response/resolution hedeflerini `paused`, onaydan sonra response/resolution/OLA hedeflerini `running`, ilk yanittan sonra response'u `met` ve fulfillment sonunda uc hedefi de `met` olarak dogrulamistir.

## Acik kapsam

UC hedefi, dead-letter replay yonetim ekrani ve notification/webhook teslim metrikleri sonraki operasyon kapisindadir. Bu nedenle genel `SLA-01` henuz tamamen kapanmis sayilmaz.
