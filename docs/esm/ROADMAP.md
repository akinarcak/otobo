# Yol Haritasi

## Gerceklesen

- [x] `FOUND-01`: kaynak koddan Docker image, Compose gelistirme profili, statik smoke testi ve GitHub Actions kalite kapisi (`2026-07-24`).
- [x] Ozel test sunucusunda izole temel kurulum: MariaDB, Redis, OTOBO web ve daemon; HTTP ve konsol smoke testleri (`2026-07-24`).
- [x] `FOUND-02`: kurulabilir `D724Foundation 0.1.0` paketi, SysConfig, JSON tanilama komutu ve 15 paket testi (`2026-07-24`).
- [x] `SEC-01a`: tenant threat modeli, varsayilan-reddet `D724TenantGuard 0.1.1`, karar/scope API'leri ve 78 negatif-pozitif test (`2026-07-24`).
- [x] `CAT-01`: tenant-guarded Service/Offering/CatalogItem semasi ve repository API'si; 30 MariaDB entegrasyon testi (`2026-07-24`).
- [x] `CAT-02a`: authenticated customer portal katalog listeleme, item detayi ve validated dinamik form render'i (`2026-07-24`).
- [x] `SEC-02`: kalici tenant/agent directory, tenant-bazli role bindings, tek-seferlik bootstrap ve lockout korumalari (`2026-07-24`).
- [x] `CAT-02b`: directory-derived tenant-admin katalog/form yonetim arayuzu, CSRF ve optimistic update kontrolleri (`2026-07-24`).
- [x] `FLOW-01`: idempotent portal submission, tenant-role onayi, fulfillment gorev durum makinesi ve agent workbench; oturumlu HTTP kabul testi (`2026-07-24`).
- [x] `SLA-01a`: tenant-safe resolution commitment policy/instance/event modeli, OTOBO business calendar hesabi, pause/resume, warning/breach sweep ve request lifecycle entegrasyonu (`2026-07-24`).
- [x] `SLA-01b-core`: response/resolution/OLA hedefleri, cevap-tabanli entitlement secimi, bagimsiz lifecycle sinyalleri ve idempotent escalation outbox (`2026-07-24`).
- [x] `SLA-01b-actions`: lease/retry/dead-letter dispatcher, tenant-role notification, fulfillment assignment ve allow-list/HMAC korumali webhook teslimi (`2026-07-24`).
- [x] `AUD-01a`: tenant-bazli normalize audit olaylari, SHA-256 hash zinciri, yetkili cursor/NDJSON export, request lifecycle adapter'i ve idempotent olay anahtarlari (`2026-07-24`).
- [ ] `SEC-01b`: katalog, case/ticket, Generic Interface, daemon, rapor, cache ve search adapter'larinda zorunlu tenant policy entegrasyonu.

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

1. `AUD-01b`: transaction/outbox ile audit completeness, OTOBO ticket/Generic Interface/SLA adapter'lari, retention/legal hold ve WORM sink
2. `SEC-01b`: kalan case/API/daemon/report/cache/search policy adapter'lari ve katalog DB constraint sertlestirmesi
3. `API-01`: tenant-safe REST API, OAuth client kimligi, rate limit ve imzali webhook sozlesmeleri
4. `OBS-01`: metrikler, dashboard ve alarm esikleri
5. `PILOT-01`: ornek IT/HR kataloglari ve pilot kabul senaryolari
