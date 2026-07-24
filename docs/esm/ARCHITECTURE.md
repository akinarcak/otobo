# Hedef Mimari

## Baslangic karari

OTOBO, ticket/workflow, kimlik, zaman planlama, Generic Interface, arama ve paket yonetimi icin sistem-of-record olarak kalir. Ilk iki surumde mikroservis donusumu yapilmaz. Yeni yetenekler once GPL-3.0 OTOBO paketleri olarak uretilir; yuksek hacimli veya bagimsiz olceklenmesi gereken isler olay tabanli yan hizmetlere ayrilir.

## Katmanlar

```text
Portal / Agent UI / Admin UI
            |
        API Gateway
            |
OTOBO Core + D724 ESM Packages ---- Event Outbox
       |          |                     |
   MariaDB     Redis Cache        Worker / Connectors
       |                                |
 Elasticsearch                    AI Gateway
```

### Cekirdek paketler

- `D724ServicePortfolio`: hizmet, teklif, sahiplik ve yasam dongusu
- `D724Catalog`: hizmet/teklif/katalog ogesi, dinamik form ve uygunluk
- `D724Request`: idempotent talep, rol-bazli onay ve fulfillment gorev durum makinesi
- `D724Commitment`: SLA/OLA/UC, takvim ve eskalasyon
- `D724TenantGuard`: organizasyon kapsami ve veri erisim politikasi
- `D724Audit`: normalize, eklemeli denetim olaylari ve kanit disari aktarimi
- `D724Automation`: olay-kosul-eylem kurallari ve guvenli webhook
- `D724AIAssist`: saglayicidan bagimsiz, insan onayli AI kullanim noktasi

Paketler birbirinin tablolarina dogrudan yazmaz; yayinlanan Perl API'lerini ve Generic Interface sozlesmelerini kullanir. Dis istemciler `/api/v1` altinda surumlu JSON sozlesmeleri kullanir. Tekrarlanan istekler idempotency anahtari tasir; webhook'lar imzali, tekrar denenebilir ve dead-letter kayitlidir.

## Veri ve tenant modeli

Ilk surum paylasimli uygulama/paylasimli sema modelidir. Tum tenant-kapsamli tablolarda zorunlu `tenant_id` bulunur ve erisim yalnizca merkezi policy servisinden gecer. Yuksek regule musteriler icin ayri deployment ticari paket olarak sunulur. Tenant anahtari olmadan calisan sorgular CI kontrolunde engellenir.

Ana varliklar: Tenant, Organization, Person, Service, ServiceOffering, CatalogItem, Case, Task, Approval, Commitment, Calendar, CI, Asset, Contract, KnowledgeArticle, AutomationRule ve AuditEvent.

## Guvenlik tabani

- OIDC/SAML SSO, MFA'nin kimlik saglayicida zorlanmasi
- RBAC + tenant/organizasyon/kayit baglamli policy kontrolu
- Secret'larin depo ve SysConfig disinda secret manager'da tutulmasi
- Aktarimda TLS, yedeklerde ve yonetilen hizmette disk/veri sifreleme
- Hassas alan maskeleme, saklama ve unutma is akislari
- SBOM, bagimlilik taramasi, imzali release artifact ve guvenlik politikasi
- Ayricalikli eylemler icin yeniden kimlik dogrulama ve eksiksiz audit

## Operasyon

Referans kurulum Docker Compose ile baslar: web, daemon, MariaDB, Redis, Elasticsearch ve Nginx. Uretim profili; harici veritabani/nesne depolama, merkezi log, OpenTelemetry metrik/trace, saglik kontrolleri, yedek ve geri donus tatbikati ekler. Kubernetes ancak olculmus musteri ihtiyaci olursa gelir.

Hedef SLO: aylik %99,9 erisilebilirlik; p95 API okuma < 500 ms; portal talep olusturma p95 < 2 sn; RPO 15 dk ve RTO 4 saat (yonetilen standart paket).

## Mimari kalite kapilari

- Yeni cekirdek yama icin Architecture Decision Record zorunlu.
- Her API icin yetki, tenant izolasyonu, hata ve idempotency testi zorunlu.
- Her sema degisikligi ileri/geri uyumlu migration ve geri donus plani tasir.
- AI sonucu kaynak, model, istem surumu ve kullanici karariyla audit edilir.
