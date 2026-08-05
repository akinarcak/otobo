# REPORT-01 Tenant-safe Operational Reporting

Durum: ilk operasyon raporu ve export guvenlik kapisi tamamlandi (`2026-07-25`).

## Sozlesme

`CareOnCloudReporting 0.4.0`, tek tenant ve inclusive tarih araligi icin su aggregate
verileri uretir:

- request status sayilari;
- catalog item key/name bazinda kullanim sayilari;
- commitment objective type/status sayilari;
- toplam request, commitment ve breached commitment sayilari.

Her SQL sorgusu bagli `tenant_id`, `from` ve `to + 1 gun` kosullarini tasir.
Tarih araligi varsayilan en fazla 366 gundur. Rapor, requester kimligi, dinamik
form cevaplari, yorumlar, idempotency key, audit actor'u veya serbest metin
workflow payload'i secmez.

## Özelleştirilebilir rapor tasarımcısı

Operasyon Merkezi, yöneticinin aynı raporda en fazla üç boyut ve dört ölçü
seçmesine izin verir. Desteklenen boyutlar durum, hizmet kategorisi, servis
uzantısı, talep türü ve aydır. Desteklenen ölçüler benzersiz talep sayısı, SLA
hedefi sayısı, ihlal sayısı ve SLA uyum yüzdesidir. İsteğe bağlı durum filtresi
uygulanabilir.

Tarayıcı veya API istemcisi SQL ifadesi gönderemez. Boyutlar, ölçüler ve filtreler
sunucudaki allowlist ile doğrulanır; bilinmeyen alanlar fail-closed reddedilir.
Üretilen her sorgu yetkilendirilmiş tenant ve doğrulanmış tarih aralığını zorunlu
koşul olarak taşır. Çoklu SLA hedeflerinin talep sayısını şişirmemesi için talep
ölçüsü `COUNT(DISTINCT request.id)` semantiğini kullanır.

Arayüz metinleri İngilizce kaynak anahtarları ve `tr_CareOnCloudReporting` Türkçe dil
modülüyle sunulur. Hücreler HTML-escape edilerek çıktı tablosuna yazılır.
Seçilen sütun düzeni CSV ve JSON dışa aktarmada korunur. Dışa aktarma ayrıca
`report.export` kararı gerektirir; CSV hücreleri sabit özette olduğu gibi formül
enjeksiyonuna karşı nötralize edilir.

## Kaydedilmiş raporlar

`CareOnCloudReporting 0.4.1`, rapor seçimini `careoncloud_report_definition` tablosunda tenant,
teknik anahtar, sahip kullanıcı ve görünürlük bilgileriyle saklar. `private`
tanımlar yalnızca sahibine, `shared` tanımlar aynı tenant içinde `report.read`
yetkisi olan kullanıcılara görünür. Tanımlar ham SQL değil, doğrulanmış boyut,
ölçü ve durum filtresi anahtarlarını JSON olarak taşır. Çalıştırıldıklarında mevcut
allowlist motorundan ve tenant yetkilendirmesinden yeniden geçerler.

Oluşturma CSRF challenge kontrolü gerektirir. Silme sorgusu tenant, rapor kimliği
ve sahip kullanıcı kimliğini birlikte bağlar; başka bir kullanıcının paylaşılan
raporu silinemez. Paket yükseltmesi tabloyu `0.4.1` adımında oluşturur.

Basarili policy kararindan sonra summary, `CareOnCloud::TenantCache` uzerinde 60 saniye
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
bin/careoncloud.Console.pl Admin::CareOnCloud::ReportExport \
  --tenant-id TENANT --from YYYY-MM-DD --to YYYY-MM-DD \
  --actor-user-id USER_ID --format csv
```

## Kanit

`development/careoncloud/Accept-Reporting.pl`, demo directory kullanicisi `47` ile
`careoncloud-demo` raporunu gercek MariaDB uzerinde uretti: 10 request, 24 commitment,
2 breached commitment. CSV ve JSON'da requester/idempotency material bulunmadi;
`report-accept-forbidden` tenant export'u `FORBIDDEN` oldu. Unit test katalog
adini `=Formula Safe` secerek CSV neutralization'i ve baska tenant etiketi ile
request'inin export edilmedigini dogruladi.

Ilk cagrinin cache miss, ikincinin hit olmasi ve iki tenantin ayni logical key ile
ayri deger okumasini da kapsayan tam CareOnCloud regresyonu 42 dosya ve 859 assertion ile gecti.
