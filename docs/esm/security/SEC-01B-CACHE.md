# SEC-01B Tenant Cache Isolation

Durum: cache alt kapisi tamamlandi (`2026-07-25`). Genel `SEC-01b`, search
adapter'i tamamlanana kadar aciktir.

## Guvenlik kontrati

`D724TenantGuard 0.5.1` icindeki `D724::TenantCache`, D724 domain kodunun OTOBO
cache'ine dogrudan tenant-belirsiz key yazmasini engelleyen ortak adapter'dir.
Her `Set`, `Get`, `Delete` ve tenant-geneli `CleanUp` islemi:

- adapter'in etkin oldugunu;
- tenant kimligi, domain ve logical key formatini;
- tenant'in veritabaninda halen aktif oldugunu;
- trusted server-side subject'in merkezi `TenantGuard` karariyla action'i alabildigini

yeniden dogrular. Herhangi bir kontrol veya backend write/cleanup hatasi fail-closed
sonuctur.

## Fiziksel namespace

Backend Type'i `D724T_<tenant SHA-256 prefix>`, key ise
`v1:<domain>:<domain+logical-key SHA-256 prefix>` bicimindedir. Tenant kimligi ve
logical key backend adresinde clear-text bulunmaz. Farkli tenantlar ayni logical key'i
kullansa bile Type'lari ayridir; bu sayede tenant-geneli invalidation diger tenantin
verisini silemez.

Adapter yalniz persistent backend'i kullanir (`CacheInMemory=0`) ve TTL'yi varsayilan
86400 saniyelik ust sinirla kontrol eder. Test kurulumunda OTOBO'nun etkin persistent
backend'i `Kernel::System::Cache::FileStorable`'dir. Compose Redis servisi sagliklidir,
ancak bu kilometre tasinda OTOBO cache backend'i Redis olarak yapilandirilmamistir.

## Ilk uretim tuketicisi

`D724Reporting 0.2.0`, tenant aggregate summary sonucunu 60 saniyelik TTL ile bu
adapter'da saklar. Hem miss hem hit yolunda once `report.read` veya `report.export`
karari verilir; cached veri authorization'i atlayamaz. Key `operational-v1` schema
surumu ile tarih araligini kapsar.

## Operasyon ve kanit

`Admin::D724::TenantCacheStatus --json`, etkinlik, TTL konfigurasyonu, backend
erisilebilirligi, backend module adi, namespace surumu ve persistent-only davranisi
raporlar.

`TenantCache.t` iki tenant icin ayni logical key ayrimini, cross-tenant reddini, TTL
ust sinirini, control-character/path enjeksiyonunu, tek-key ve tenant-geneli izole
invalidation'i, inactive tenant ile disabled adapter fail-closed davranisini test eder.
`Accept-TenantCache.pl` ayni matrisi calisan MariaDB ve persistent OTOBO backend'i
uzerinde gecici tenant fixture'lariyla calistirip temizler.

Hedefli regresyon 6 dosya / 172 test, tam D724 regresyonu 41 dosya / 834 test ile
`PASS` sonucudur. Canli kabul `namespace_isolated`, `cross_tenant_denied` ve
`cleanup_isolated` alanlarini `true` dondurmustur.
