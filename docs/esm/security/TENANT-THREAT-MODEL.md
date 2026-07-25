# SEC-01 Tenant Threat Modeli

Durum: policy cekirdegi ve OTOBO ticket write-scope cekirdegi uygulandi; API ve kalan read/query entegrasyon kapilari acik.

## Guvenlik siniri

Bir tenant; organizasyonlari, kisileri, talepleri, hizmetleri, varliklari, sozlesmeleri, bilgi makalelerini, otomasyonlari ve audit olaylarini kapsayan en ust veri siniridir. OTOBO `CustomerID`, kuyruk ve grup yetkileri operasyonel erisim mekanizmalaridir; tek baslarina D724 tenant siniri sayilmazlar. D724 kodu bir kaynagi okumadan veya degistirmeden once merkezi `D724TenantGuard` kararini almak zorundadir.

## Degismezler

1. Tenant bilgisi olmayan subject veya resource icin karar her zaman reddir.
2. Bilinmeyen action ve role varsayilan olarak reddedilir.
3. Tenant kimlikleri tam, buyuk/kucuk harf duyarli ve normalize edilmeden karsilastirilir.
4. Kaynak tenant'i, subject'in acik tenant kapsaminda degilse erisim reddedilir.
5. `platform_admin` rolu tek basina global erisim vermez; ayrica kapali gelen acil durum ayari etkin olmalidir.
6. Query once tenant scope ile daraltilir, sonra her kayit icin action karari uygulanir.
7. UI'da gizlemek yetki kontrolu degildir; Generic Interface, daemon, console ve otomasyon ayni policy servisini kullanir.
8. Karar nedeni audit edilebilir, fakat son kullaniciya baska tenant'in varligini gosteren ayrinti donulmez.
9. Tenant degisikligi normal update degildir; kontrollu transfer is akisi ve iki tarafli yetki gerektirir.
10. Policy servisi hata verirse veya yapilandirma okunamazsa islem reddedilir.

## Tehditler ve kontroller

| Tehdit | Ornek | Kontrol | Kanit |
|---|---|---|---|
| IDOR | `/case/42` ile baska tenant kaydi | Resource TenantID + merkezi karar | cross-tenant matris testleri |
| Eksik filtre | rapor sorgusunda tenant kosulu unutulmasi | `ScopeGet` bos/invalid kapsamda basarisiz | scope testleri; repository entegrasyon testi sonraki kapida |
| Yetki yukseltme | kullanicinin role parametresi gondermesi | roller yalnizca guvenilir server context'inden | API adapter threat testi sonraki kapida |
| Kuyruk yan gecisi | ortak agent grubunun iki musteri kaydini gormesi | OTOBO grup izninden sonra TenantGuard | ticket permission adapter sonraki kapida |
| Arka plan sizintisi | daemon job'unun tenantsiz calismasi | aktif TenantID + tenant-bound `automation:<job>` subject + merkezi `automation.execute` | commitment sweep/webhook scan/dispatcher negatif entegrasyon testleri (`SEC-01b-daemon`) |
| Cache karismasi | tenant anahtari olmayan cache key | aktif tenant + policy kontrolu, hash'li tenant Type ve izole invalidation | `TenantCache.t`, `TenantCacheStatus.t`, `Accept-TenantCache.pl` |
| Arama sizintisi | global Elasticsearch sonucu | index dokumaninda TenantID + zorunlu filter | search profili sonraki kapida |
| Export sizintisi | raporun tum kayitlari indirmesi | her SQL'de tenant+tarih predicate, `report.read`/`report.export`, aggregate-only schema | D724Reporting cross-tenant/PII/CSV negatif testleri ve demo kabulü (`SEC-01b-report`) |
| Global admin kotuye kullanimi | tek rolle tum tenant'lara giris | iki anahtarli opt-in, audit ve acil durum runbook'u | platform admin config testleri |
| Kimlik karmasasi | bosluk/case ile benzer tenant ID | dar kimlik regex'i ve exact match | invalid/case-sensitive testler |

## Ilk rol/action matrisi

| Rol | Izinler |
|---|---|
| `requester` | `catalog.read`, `case.create`, `case.read`, `case.comment` |
| `agent` | requester izinleri + `case.update`, `case.assign` |
| `service_owner` | agent izinleri + `catalog.manage`, `case.delete`, `audit.read` |
| `auditor` | `catalog.read`, `case.read`, `audit.read` |
| `automation` | agent operasyonlari; silme ve tenant yonetimi yok |
| `tenant_admin` | bilinen tum tenant-ici action'lar |
| `platform_admin` | yalnizca `AllowPlatformAdmin=1` ise bilinen tum action'lar |

Bu matris urun API'sinin sozlesmesidir. Yeni action eklemek varsayilan olarak hicbir role izin vermez; rol eslemesi ve negatif test ayni degisiklikte eklenmelidir.

## Entegrasyon kapilari

Policy cekirdeginin basarili olmasi tek basina tenant izolasyonunu tamamlamaz. `SEC-01` ancak su adapter'lar da policy cagirip negatif entegrasyon testlerinden gectiginde tam kapanir:

- katalog repository/API,
- case/ticket get-search-update,
- Generic Interface operasyonlari,
- daemon ve otomasyon job'lari,
- rapor/export,
- cache ve search indexleri.

Bu nedenle mevcut durum "policy primitive verified", ticari multi-tenant guvencesi degildir.
