# Yol Haritasi

Takvim, iki haftalik sprint ve her asamada calisan urun varsayimiyla yazildi. Tarihler ekip kapasitesi dogrulandiktan sonra sabitlenmelidir.

## Faz 0 - temel (hafta 1-4)

- Marka gecici adi, lisans bildirimi ve katkici politikasi
- Upstream senkronizasyonu ve release dal modeli
- Docker gelistirme ortami ve tek komutlu smoke test
- Paket iskeletleri, CI, kod politikasi, SBOM ve guvenlik taramasi
- Ana veri modeli ve tenant threat-model calismasi

Cikis: temiz kurulum, test, paket yukleme ve upstream merge islemleri CI'da tekrarlanabilir; lisans dosyalari release paketinde bulunur.

## Faz 1 - ESM MVP (ay 2-4)

- Hizmet portfoyu ve katalog yonetimi
- Dinamik talep formu, onay ve fulfillment gorevleri
- SLA/OLA takvimi, eskalasyon ve operasyon panosu
- Tenant guard, audit export ve temel REST API
- Turkce/Ingilizce agent ve portal metinleri

Cikis: tasarim ortagi bir musteri IT ve HR kataloglarini kurup uctan uca talep isletebilir; kritik izolasyon ve SLA testleri gecmektedir.

## Faz 2 - satilabilir surum (ay 5-7)

- Problem, change ve major incident deneyimi
- CMDB servis haritasi ve varlik baglami
- SSO, SCIM, e-posta ve imzali webhook baglantilari
- Yedek/geri donus, gozlemlenebilirlik ve yonetilen hizmet runbook'lari
- Kurulum sihirbazi, ornek kataloglar ve yonetici rehberi

Cikis: 3 tasarim ortaginda 90 gunluk pilot, sifir tenant veri sizintisi, kritik akislarda >= %99 basari ve belgelenmis upgrade provasi.

## Faz 3 - akilli ESM (ay 8-10)

- Ozet, siniflandirma, benzer kayit ve bilgi onerisi
- PII maskeleme, saglayici politikasi, maliyet/latency limitleri
- Insan onayli otomasyon ve AI kalite degerlendirme seti
- SLA riski ve bilgi boslugu panolari

Cikis: oneri kabul orani >= %50, ortalama isleme suresinde >= %20 azalma; yanlis otomatik kapanis veya onaysiz yuksek etkili eylem yok.

## Faz 4 - genel kullanim (ay 11-12)

- Veri ice/disa aktarim araclari ve surum yukseltme asistani
- Yuk/guvenlik testleri, felaket kurtarma tatbikati ve dis sizma testi
- Fiyatlama, destek seviyeleri, SLA ve partner egitimi
- `1.0.0` kaynak, container, SBOM, imza ve release notlari

## Ilk backlog sirasi

1. `FOUND-01`: yerel Docker gelistirme profili ve smoke test
2. `FOUND-02`: D724 paket sablonu ve CI kalite kapilari
3. `SEC-01`: tenant policy servisinin threat modeli ve test matrisi
4. `CAT-01`: Service/Offering/CatalogItem semasi ve yonetim API'si
5. `CAT-02`: portal katalog listeleme ve dinamik form
6. `FLOW-01`: onay + fulfillment orkestrasyonu
7. `SLA-01`: commitment motoru ve takvim hesaplari
8. `AUD-01`: normalize audit event ve disari aktarim
9. `OBS-01`: metrikler, dashboard ve alarm esikleri
10. `PILOT-01`: ornek IT/HR kataloglari ve pilot kabul senaryolari
