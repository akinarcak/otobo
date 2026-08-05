# CareOnCloud ESM satış demosu

Showcase veri seti tamamen sentetiktir. Adlar ve süreçler Türkiye bankacılık,
hazır giyim ve çok mağazalı perakende operasyonlarını anlatmak için üretilmiştir;
hiçbir gerçek şirketin CareOnCloud müşterisi veya referansı olduğu iddia edilmez.

## Demo tenantları

| Tenant | Portal kullanıcısı | Senaryo |
|---|---|---|
| Marmara Bank Demo | `bank.demo` | Kritik uygulama erişimi ve şube cihazı |
| Anadolu Moda Demo | `moda.demo` | Tasarım iş istasyonu ve e-ticaret ürün yayını |
| Perakende360 Demo | `retail.demo` | POS arızası ve yeni mağaza açılışı |

Ortak demo parolası deployment sırasında `CAREONCLOUD_DEMO_PASSWORD` ortam
değişkeninden alınır; repoya yazılmaz. Seed idempotenttir ve domain API'lerini
kullanır. Her tenant için 2 katalog öğesi ve 12 talep oluşturulur:

- 6 `fulfilled`
- 2 `awaiting_approval`
- 2 `in_fulfillment`
- 1 `rejected`
- 1 `fulfillment_failed`

```text
CAREONCLOUD_DEMO_PASSWORD=<secret> perl -I. -IKernel/cpan-lib -ICustom \
  /tmp/Seed-CareOnCloudShowcase.pl
```

`Generate-CareOnCloudDemoReports.pl`, tenant yetkili Reporting servisi üzerinden
her tenant için JSON/CSV ve bir `executive-summary.json` üretir. Raporlar PII ve
serbest metin içermez.
