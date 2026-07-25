# WEBHOOK-01 - Imzali Teslimat Sozlesmesi

## Kapsam

`D724Commitment 0.5.0`, SLA/OLA escalation outbox'indaki webhook aksiyonlarini
tenant-safe, tekrar denenebilir ve denetlenebilir bicimde teslim eder. Endpoint
URL ve secret veritabaninda tutulmaz; policy yalniz adlandirilmis endpoint
anahtarini tasir. Deployment konfigurasyonu bu anahtari URL/secret kaydina
cozer ve URL'nin HTTPS host'u exact allow-list'te olmak zorundadir.

`D724Webhook 0.3.0` ayni teslimat cekirdeginin uzerine genel lifecycle
aboneliklerini ekler. Ayri bir retry motoru veya teslimat tablosu yoktur.

## Endpoint konfigurasyonu

Endpoint URL ve secret API veya abonelik tablosunda tutulmaz. Deployment,
`D724::Commitment::WebhookEndpoints` hash'ine `endpoint::URL` ve
`endpoint::Secret` alanlarini; `WebhookAllowedHosts` listesine exact HTTPS
host'u yazar. Ornek endpoint anahtari `lifecycle` icin alanlar
`lifecycle::URL` ve `lifecycle::Secret` olur. Secret en az 32 karakterdir.

## Lifecycle abonelikleri

Tenant administrator su canonical endpoint'leri kullanir:

- `POST|GET /otobo/api/v1/webhook-subscriptions`
- `GET|PATCH /otobo/api/v1/webhook-subscriptions/{subscription_id}`

Create kontrati `key`, `name`, `endpoint_key` ve 1-20 `event_patterns` ister.
Pattern exact action (`request.created`) veya prefix wildcard (`request.*`)
olabilir. URL/secret istemci tarafindan verilemez. `start_sequence` atlanirsa
abonelik tenant audit head'inden baslar; acik catch-up cursor'u `0..head`
araliginda olmalidir. Update `expected_version` ile optimistic lock uygular ve
aboneligi `active|inactive` yapabilir.

Tarayici immutable `d724_audit_event` zincirini tenant + subscription cursor'u
ile sirali okur. Eslesen olay `(tenant, subscription, audit sequence)` icin
ortak `d724_escalation_outbox` tablosuna tek kayit yazar; outbox yazimi ve cursor
ilerlemesi ayni transaction'dadir. Crash sonrasi cursor geri kalirsa unique
anahtar mevcut delivery'yi idempotent replay olarak tanir. Payload schema v1;
tenant, subscription ID/key ve normalize event identity/state/hash/details
alanlarini tasir.

## HTTP teslimati

- Method: `POST`
- Content-Type: `application/json`
- Body: outbox olusturulurken canonical ve key-sorted uretilen JSON payload
- TLS: sertifika ve hostname dogrulamasi varsayilan olarak zorunlu
- Redirect/host hedefi: sadece deployment allow-list'indeki exact HTTPS host

Basliklar:

```text
X-D724-Signature-Version: v1
X-D724-Signature-Timestamp: 2026-07-27 12:34:56
X-D724-Delivery-ID: 9002
X-D724-Tenant: tenant-key
X-D724-Signature-256: sha256=<64 lowercase hex>
```

`X-D724-Signature-Timestamp` UTC'dir. Imzalanan byte dizisi asagidaki gibi
olusturulur; bosluk veya JSON'u yeniden encode etmek imzayi degistirir:

```text
v1 + "." + timestamp + "." + delivery_id + "." + exact_request_body
```

Imza `HMAC-SHA256(signing_string, endpoint_secret)` degeridir. Secret en az 32
karakter olmalidir.

Receiver su sirayla fail-closed dogrulama yapmalidir:

1. signature version `v1` olmali;
2. timestamp izin verilen replay penceresinde olmali (onerilen: 5 dakika);
3. HMAC sabit-zamanli karsilastirma ile dogrulanmali;
4. delivery ID daha once basariyla islendiyse ayni sonuc idempotent donmeli;
5. body tenant degeri ile beklenen tenant eslesmeli;
6. sadece tum kontrollerden sonra domain side effect uygulanmali.

Herhangi bir `2xx` cevap teslim edilmis sayilir. Diger cevaplar exponential
backoff ile yeniden denenir ve maksimum deneme sonunda `dead` olur.

## Dead-letter replay

Yalniz tenant administrator su onayli komutla tek bir dead-letter kaydini
yeniden kuyruklayabilir:

```text
bin/otobo.Console.pl Admin::D724::CommitmentReplay \
  --tenant-id TENANT --outbox-id ID --expected-attempt-count COUNT \
  --actor-user-id USER_ID --confirm
```

`expected-attempt-count` optimistic lock'tur. Replay mevcut cycle attempt
sayacini sifirlar; `lifetime_attempt_count` korunur ve `replay_count` artar.
Durum degisikligi ile `commitment.escalation_replayed` audit append'i ayni DB
transaction'indadir. Dead olmayan, baska tenant'a ait veya stale bir kayit
yeniden kuyruklanmaz.

## Operasyon kaniti

`Admin::D724::CommitmentStatus --json` pending/retry/processing/delivered/dead
sayaclarini, webhook delivered/dead sayaclarini, lifetime attempt ve replay
toplamlarini raporlar.

`Admin::D724::WebhookStatus --json`, genel lifecycle abonelik outbox'u icin
pending, retry, dead, son bir saatte delivered ve en eski hazir teslimat yasini
raporlar. Varsayilan backlog ve yas esikleri `100` teslimat ve `10` dakikadir;
tek bir dead-letter dahi saglik alarmi uretir. Sorgu/config hatasi yapisal
`Success` degerini fail-closed yapar; operasyonel esik asimi `Health.Healthy`
alaninda ayrica gorulur.

`development/d724/Accept-CommitmentReplay.pl` ile `d724-demo` uzerinde gercek
MariaDB kabul testi yapildi (`2026-07-25`): outbox `51` icin cross-tenant replay
`FORBIDDEN`, stale attempt `VERSION_CONFLICT`, dead→retry→delivered basarili,
attempt/replay/lifetime sayaclari `1/1/4` ve tek audit olayi dogrulandi.
`Accept-WebhookSubscription.pl` gercek canonical HTTP uzerinde requester create
`403`, tanimsiz endpoint `422`, tenant-admin create/list/get/disable
`201/200/200/200` ve stale update `409` kanitladi. Audit sequence `116`, shared
outbox `74` ile tek kez teslim edildi. Son paketlerle tum D724 regresyonu 42
dosya ve 859 assertion olarak birlikte gecti; web, daemon, MariaDB ve Redis
servisleri saglikli kaldi.
