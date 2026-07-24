# WEBHOOK-01 - Imzali Teslimat Sozlesmesi

## Kapsam

`D724Commitment 0.4.0`, SLA/OLA escalation outbox'indaki webhook aksiyonlarini
tenant-safe, tekrar denenebilir ve denetlenebilir bicimde teslim eder. Endpoint
URL ve secret veritabaninda tutulmaz; policy yalniz adlandirilmis endpoint
anahtarini tasir. Deployment konfigurasyonu bu anahtari URL/secret kaydina
cozer ve URL'nin HTTPS host'u exact allow-list'te olmak zorundadir.

Bu dilim genel lifecycle subscription API'si degildir. Request, incident,
change ve diger domain olaylari icin yonetilebilir abonelikler ayni teslimat
cekirdeginin uzerinde sonraki dilimde eklenecektir.

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

`development/d724/Accept-CommitmentReplay.pl` ile `d724-demo` uzerinde gercek
MariaDB kabul testi yapildi (`2026-07-25`): outbox `51` icin cross-tenant replay
`FORBIDDEN`, stale attempt `VERSION_CONFLICT`, dead→retry→delivered basarili,
attempt/replay/lifetime sayaclari `1/1/4` ve tek audit olayi dogrulandi.
Son paketle tum D724 regresyonu 32 dosya ve 641 assertion olarak birlikte
gecti; web, daemon, MariaDB ve Redis servisleri saglikli kaldi.
