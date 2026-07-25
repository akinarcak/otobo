# REPORT-01 Tenant-safe Operational Reporting

Durum: ilk operasyon raporu ve export guvenlik kapisi tamamlandi (`2026-07-25`).

## Sozlesme

`D724Reporting 0.2.0`, tek tenant ve inclusive tarih araligi icin su aggregate
verileri uretir:

- request status sayilari;
- catalog item key/name bazinda kullanim sayilari;
- commitment objective type/status sayilari;
- toplam request, commitment ve breached commitment sayilari.

Her SQL sorgusu bagli `tenant_id`, `from` ve `to + 1 gun` kosullarini tasir.
Tarih araligi varsayilan en fazla 366 gundur. Rapor, requester kimligi, dinamik
form cevaplari, yorumlar, idempotency key, audit actor'u veya serbest metin
workflow payload'i secmez.

Basarili policy kararindan sonra summary, `D724::TenantCache` uzerinde 60 saniye
saklanir. Logical key schema surumu ve tarih araligini tasir; fiziksel Type tenant
kimliginin SHA-256 turevidir. Her hit/miss isteginde authorization yeniden calisir;
cache bir yetki atlama mekanizmasi degildir. Rapor verisi en fazla 60 saniye gecikmeli
olabilir ve bu sinir SysConfig ile daha da dusurulebilir.

## Yetkilendirme

Policy contract `1.3.0` iki yeni default-deny action tanimlar:

- `report.read`: `auditor`, `service_owner`, `tenant_admin`;
- `report.export`: `auditor`, `service_owner`, `tenant_admin`.

Agent ve requester bu action'lari alamaz. Subject ya server-side role binding
ile verilir ya da kalici tenant directory'den `UserID` ile uretilir. Tenant
istemci parametresinin subject scope'unda olmamasi `FORBIDDEN` sonucudur.

## Export

JSON schema version `1` ve CSV desteklenir. CSV tum hucreleri quote eder, CR/LF
karakterlerini temizler ve `=`, `+`, `-`, `@` ile baslayan degerleri spreadsheet
formula injection'a karsi apostrofla neutralize eder. Dosya adi tenant ve tarih
araligindan guvenli karakterlerle uretilir.

Konsol kullanimi:

```text
bin/otobo.Console.pl Admin::D724::ReportExport \
  --tenant-id TENANT --from YYYY-MM-DD --to YYYY-MM-DD \
  --actor-user-id USER_ID --format csv
```

## Kanit

`development/d724/Accept-Reporting.pl`, demo directory kullanicisi `47` ile
`d724-demo` raporunu gercek MariaDB uzerinde uretti: 10 request, 24 commitment,
2 breached commitment. CSV ve JSON'da requester/idempotency material bulunmadi;
`report-accept-forbidden` tenant export'u `FORBIDDEN` oldu. Unit test katalog
adini `=Formula Safe` secerek CSV neutralization'i ve baska tenant etiketi ile
request'inin export edilmedigini dogruladi.

Ilk cagrinin cache miss, ikincinin hit olmasi ve iki tenantin ayni logical key ile
ayri deger okumasini da kapsayan tam D724 regresyonu 42 dosya ve 859 assertion ile gecti.
