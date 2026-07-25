# Yol Haritasi

## Gerceklesen

- [x] `BRAND-01`: CareOnCloud ESM ürün adı, resmi Careon logosu, `Hizmet Bulutta, Kontrol Sizde.` sloganı ve agent/müşteri giriş yüzeyleri (`2026-07-25`).
- [x] `DEMO-01`: Cloudflare Tunnel ile `esm.arcak.net`, üç sentetik sektör tenant'ı, 36 örnek talep, 99 commitment ve kapasite/kullanım ayrımlı raporlar (`2026-07-25`).
- [x] `CAT-03`: DD-YHE-02-R1 kaynaklı 6 alan/51 hizmetlik yönetilen hizmet kataloğu, DORA iz alanları ve dört demo tenant'ına idempotent kurulum (`2026-07-25`).
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
- [x] `AUD-01b-request`: request create/approval/response/task/fulfillment mutasyonlari ile audit append'ini tek DB transaction'inda atomiklestirme; hata enjeksiyonu, retry ve concurrent dedupe kaniti (`2026-07-24`).
- [x] `AUD-01b-catalog`: service/offering/item/schema create-update mutasyonlari icin normalize, tenant-safe ve transaction-atomic audit adapter'i (`2026-07-24`).
- [x] `AUD-01b-directory`: tenant create/update ve membership grant/revoke mutasyonlari icin normalize audit, membership versioning, tenant-row lock ve transaction-atomic rollback (`2026-07-24`).
- [x] `AUD-01b-ticket-core`: OTOBO ticket create ile title/queue/customer/lock/state/owner/responsible/priority ve DB-backed MIME article create icin immutable tenant scope, transaction-atomic audit ve legacy migration kapisi (`2026-07-24`).
- [x] `SEC-01b-ticket`: OTOBO TicketSearch sorgu-oncesi tenant filtresi, raw bypass reddi, immutable-scope tekil okuma ve Generic Interface ortak get/history/update tenant kapisi (`2026-07-24`).
- [x] `SEC-01b-daemon`: commitment sweep, escalation dispatcher ve lifecycle webhook scanner icin aktif-tenant dogrulamasi, tenant-bound automation subject, merkezi `automation.execute` karari ve fail-closed health (`2026-07-25`).
- [x] `SEC-01b-report`: PII-minimize request/catalog/commitment operasyon raporu, tenant-bound `report.read`/`report.export`, tarih siniri, CSV formula korumasi ve gercek cross-tenant export reddi (`2026-07-25`).
- [x] `SEC-01b-cache`: aktif tenant ve merkezi policy ile fail-closed cache adapter'i, hash'li tenant namespace'i, TTL siniri, izole invalidation ve raporlama entegrasyonu (`2026-07-25`).
- [x] `SEC-01b-search-boundary`: trusted tenant context, merkezi `search.read`, final Elasticsearch request'inde zorunlu tenant filter'i ve filtresiz/unsafe-index fail-closed kapisi (`2026-07-25`).
- [x] `SEC-01b-search-runtime`: private Elasticsearch 8.19.3, resmi connection testi, ticket index migration, authoritative rebuild ve gercek iki-tenant hit/miss kabul kaniti (`2026-07-25`).
- [x] `OBS-01a`: authenticated Prometheus 0.0.4 endpoint'i, 20 sabit-labelsiz seri, API/webhook alarm bayraklari ve gercek `401/401/200` scrape kabulu (`2026-07-25`).
- [x] `API-01a`: tenant-bazli client credentials, bcrypt secret, digest-only opaque token, atomik rate limit, auditli client revoke ve tenant-scope vaka read HTTP API'si (`2026-07-24`).
- [x] `API-01b-core`: canonical `/api/v1`, OpenAPI 3.1, requester-owned request read ve transaction-atomic/idempotent request create (`2026-07-24`).
- [x] `API-01c-credentials`: optimistic ve transaction-atomic secret rotation, tum tokenlari aninda revoke, token lifecycle audit, retention cleanup ve operasyonel API sayaclari (`2026-07-25`).
- [x] `API-01b-lifecycle`: tenant-role korumali approval ve fulfillment task write endpoint'leri, optimistic version, guvenli replay, commitment senkronu ve integration actor audit (`2026-07-25`).
- [x] `SLA-01b-ops`: canonical JSON/HMAC v1 webhook kontrati, tenant-safe dead-letter replay, lifetime/replay kaniti ve teslimat metrikleri (`2026-07-25`).
- [x] `API-01c-webhook`: tenant-admin lifecycle subscription CRUD API'si, exact/prefix event filtreleri, immutable audit cursor tarayicisi ve ortak imzali outbox uzerinde exactly-once kuyruklama (`2026-07-25`).
- [x] `SEC-01b`: katalog/ticket/GI/daemon/report/cache/search tenant sınırı; Generic Interface operasyon-bazlı action matrisi ve üç composite katalog parent constraint'i (`2026-07-25`).
- [x] `SEC-03a`: exact issuer/audience tenant route'u, doğrulanmış-claim sözleşmesi, domain ve grup→rol allow-list'i, immutable subject/login bağı (`2026-07-25`).
- [x] `SEC-03b-core`: OIDC state/nonce, PKCE S256, browser binding, aynı-origin HTTPS metadata/JWKS politikası, yerleşik imza doğrulayıcı delegasyonu ve tek-kullanımlık callback (`2026-07-25`).
- [x] `SEC-03b-pkce`: OTOBO OAuth2 authorization URL ve token exchange katmanlarında RFC 7636 S256 challenge/verifier taşıma ve fail-closed doğrulama (`2026-07-25`).
- [x] `SEC-03b-web-core`: tenant/provider/surface bağlı agent-customer auth adapter'i, güvenli flow cookie'si, mevcut auth backend fallback'i, preprovision ve aktif tenant üyeliği kapısı (`2026-07-25`).

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

1. `AUD-01b-core`: kalan ticket delete/merge/type/service/SLA/pending ve Chat article, Generic Interface/SLA scheduler mutasyonlari icin transaction/outbox audit completeness, retention/legal hold ve WORM sink
2. `SEC-03b-idp/SEC-03c`: gerçek dış IdP uçtan uca kabulü ve logout/session politikası; ardından SCIM 2.0 yaşam döngüsü ve membership reconciliation
3. `API-01d-ops` (tamamlandi, 2026-07-25): bounded-cardinality route latency/error metrikleri, 168 saat retention, webhook throughput/backlog/dead-letter alarmlari ve 12 bagimsiz writer concurrent kabul testi
4. `OBS-01b`: operasyon dashboard'u, OpenTelemetry export'u ve alarm teslim kanallari (Prometheus cekirdegi tamamlandi)
5. `PILOT-01`: ornek IT/HR kataloglari ve pilot kabul senaryolari
