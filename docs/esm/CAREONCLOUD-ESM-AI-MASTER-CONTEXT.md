# CareOnCloud ESM — AI Master Context, Product Goal and Technical Handover

**Belge sürümü:** 1.0  
**Tarih:** 2 Ağustos 2026  
**Kullanım amacı:** Bu dosya, CareOnCloud ESM projesi üzerinde çalışacak yeni bir ChatGPT oturumuna, özel GPT'ye, AI coding agent'a veya teknik ekibe tek dosyada yeterli başlangıç bağlamı sağlamak için hazırlanmıştır.

---

## 0. Bu dosyayı okuyan yapay zekâya zorunlu talimat

Bu projede çalışmaya başlamadan önce bu dosyanın tamamını oku.

Aşağıdaki kurallar zorunludur:

1. CareOnCloud ESM'nin mevcut kodunu ve tamamlanmış çalışmaları koru.
2. Toplu `reset`, `checkout`, yeniden fork etme veya projeyi sıfırdan kurma işlemi yapma.
3. Bir özelliğin tamamlandığını yalnızca dokümana veya dosya sayısına bakarak kabul etme.
4. Kaynak kod paketi verilmişse iddiaları kod, test ve çalışma çıktıları üzerinden doğrula.
5. “Test dosyası var” ile “test güncel kaynak üzerinde başarıyla çalıştı” ifadelerini birbirinden ayır.
6. Üretim hazır, tam tenant izolasyonu, değiştirilemez audit veya ServiceNow alternatifi gibi güçlü iddiaları kanıt olmadan kullanma.
7. Parola, token, private key, `.env`, müşteri verisi veya başka secret'ları dokümana ve Git'e yazma.
8. Her önemli değişiklikten önce mevcut Git durumunu, aktif dalı, HEAD commit'ini ve çalışma ağacını kaydet.
9. Mevcut ürün kapsamını büyütmeden önce güvenlik, test, release ve operasyon eksiklerini kapat.
10. CareOnCloud ESM'nun kaynak kökeni GitHub, README, NOTICE, telif ve GPL alanlarında korunmalıdır; fakat son kullanıcı ürünü ve marka deneyiminde CareOnCloud ESM görünmemelidir.
11. GPL-3.0 lisansının korunması bir sorun değildir ve ürünün açık kaynak kalması hedeflenmektedir.
12. CareOnCloud'un uzun vadeli hedefi CareOnCloud ESM markasından ve runtime bağımlılığından aşamalı olarak ayrılmaktır; bu ayrışma adapter ve domain sınırlarıyla yapılmalıdır.
13. Kullanıcı tarafından açıkça istenmedikçe canlı sunucuda yıkıcı işlem yapma.
14. Belirsizlik varsa tahmin yürütmek yerine eksik kanıtı açıkça belirt.
15. Her çalışma sonunda `STATUS.md` veya eşdeğer durum kaydını güncelle; yapılan iş, test sonucu, açık risk ve geri dönüş adımını yaz.

---

# 1. Ürün kimliği

## 1.1 Ürün adı

**CareOnCloud ESM**

Slogan:

> **Hizmet Bulutta, Kontrol Sizde.**

Geçmiş geliştirme kod adlarında ve paket adlarında `D724` kullanılmaktadır. Bu ad teknik namespace olarak bir süre daha kalabilir; son kullanıcı markası CareOnCloud ESM'dir.

## 1.2 Ürünün kökeni

CareOnCloud ESM, başlangıçta:

- `RotherOSS/otobo`
- `rel-11_1` tabanı

üzerinden fork edilerek geliştirilmiştir.

GitHub'da ve kaynak dağıtımında açıkça şu anlam korunmalıdır:

> CareOnCloud ESM was originally forked from the GPL-3.0 licensed OTOBO project maintained by Rother OSS GmbH. CareOnCloud ESM is independently developed and is not affiliated with or endorsed by Rother OSS GmbH.

Türkçe karşılığı:

> CareOnCloud ESM, başlangıçta Rother OSS GmbH tarafından geliştirilen GPL-3.0 lisanslı OTOBO projesinden fork edilmiştir. CareOnCloud ESM bağımsız olarak geliştirilmektedir ve Rother OSS GmbH ile resmi bir bağlantısı veya onayı bulunmamaktadır.

CareOnCloud ESM'nun telif bildirimleri, geçmiş katkıcıları ve GPL şartları silinmemelidir.

## 1.3 Marka hedefi

Nihai ürünün kullanıcıya görünen yüzünde aşağıdaki CareOnCloud ESM unsurları bulunmamalıdır:

- CareOnCloud ESM adı ve logosu
- CareOnCloud ESM favicon ve görselleri
- CareOnCloud ESM markalı giriş, müşteri, agent ve admin ekranları
- CareOnCloud ESM footer ve yardım bağlantıları
- CareOnCloud ESM markalı e-posta şablonları
- Kullanıcıya görünen `/careoncloud/` yolları
- CareOnCloud ESM dokümantasyon bağlantıları
- CareOnCloud ESM'ya özel ürün terminolojisi
- CareOnCloud ESM adlı DB, container, volume, cookie, header ve runtime path'leri

CareOnCloud ESM kökeni yalnızca aşağıdaki alanlarda kalabilir:

- GitHub repository geçmişi
- README
- NOTICE
- UPSTREAM.md
- LICENSE ve telif bildirimleri
- Üçüncü taraf lisans kayıtları
- Kaynak kod içinde hukuken korunması gereken geçmiş atıflar

## 1.4 Lisans ve ticari yaklaşım

Ürün GPL-3.0 olarak kalacaktır. GPL'den çıkmak hedef değildir.

Ticari gelir modeli kaynak kodu kilitlemek yerine şu alanlardan üretilir:

- Onaylı ve test edilmiş build
- Kurulum
- Upgrade
- Entegrasyon
- Eğitim
- Danışmanlık
- İş saatleri veya 7×24 destek
- HA/DR
- Uyumluluk paketi
- Yönetilen hizmet
- Barındırma
- İzleme
- Yedekleme
- Operasyon SLA'sı

Önerilen paketler:

- **Community:** Kaynak kod ve topluluk dokümantasyonu
- **Professional:** Onaylı build, upgrade ve iş saatleri desteği
- **Enterprise:** SSO/SCIM, HA/DR, 7×24 destek ve uyum
- **Managed:** Hosting, izleme, yedek, güncelleme ve operasyon SLA'sı

İlk ticari dağıtımdan önce açık kaynak lisansı ve marka hukuku konusunda avukat incelemesi yapılmalıdır.

---

# 2. Ürün amacı ve konumlandırması

## 2.1 Ana amaç

CareOnCloud ESM; ITSM ile sınırlı olmayan, aşağıdaki kurumsal hizmetleri tek katalog ve sorumluluk modeli altında yöneten bir Enterprise Service Management platformudur:

- IT
- İnsan Kaynakları
- Tesis ve idari işler
- Perakende operasyonu
- Saha hizmetleri
- Yönetilen hizmetler
- Müşteri hizmetleri
- Tedarikçi ve sözleşme süreçleri

Ürün ServiceNow veya 4me'nin bütün genişliğini ilk sürümde kopyalamayı amaçlamaz.

İlk güçlü değer önerisi:

> Türkçe deneyimi güçlü, hızlı kurulabilen; hizmet kataloğu, talep orkestrasyonu, SLA, tenant kontrollü MSP kullanımı, audit ve açık API sunan GPL-3.0 ESM platformu.

## 2.2 İlk hedef pazar

- 100–2.000 veya kontrollü biçimde 5.000 kullanıcıya kadar kurumlar
- Türkçe hizmet masası ekipleri
- MSP'ler
- IT dışındaki İK ve tesis taleplerini dijitalleştirmek isteyen şirketler
- Ayrı deployment modelini kabul eden regüle müşteriler
- Açık kaynak, veri taşınabilirliği ve self-hosting isteyen kurumlar

“ServiceNow'un tam alternatifi” veya “4me ile tam özellik eşitliği” iddiası ilk ticari sürümde kullanılmamalıdır.

## 2.3 Temel kullanıcılar

- **Hizmet alan / müşteri:** Katalogdan talep açar, durum ve taahhütleri görür.
- **Agent / uzman:** Kuyruk, görev, bilgi, CI/varlık ve SLA bağlamında çalışır.
- **Hizmet sahibi:** Katalog, kapasite, maliyet, SLA/OLA ve iyileştirme verisini yönetir.
- **Platform yöneticisi:** Tenant, kimlik, yetki, entegrasyon ve otomasyonu kurar.
- **MSP yöneticisi:** Çok müşterili ortamda sözleşme ve veri sınırlarını yönetir.
- **Denetçi:** Audit ve kanıt dışa aktarımını inceler.

---

# 3. Değiştirilemez ürün gereksinimleri

## 3.1 Türkçe ve İngilizce

Ürün hem Türkçe hem İngilizce çalışmalıdır.

Yalnızca menüler değil, aşağıdaki tüm içerikler çevrilebilir olmalıdır:

- Hizmet alanları
- Hizmet kategorileri
- Hizmet adları
- Hizmet sunumları / Service Offering
- Talep tipleri / katalog öğeleri
- Dinamik form alanları
- Yardım metinleri
- Durumlar
- E-posta ve bildirim şablonları
- Dashboard ve rapor adları
- Bilgi makaleleri
- Hata mesajları
- Tarih, saat, sayı ve saat dilimi gösterimi

Kod içinde son kullanıcıya gösterilen sabit metin bırakılmamalıdır.

## 3.2 Hizmet kataloğu

Uzun vadeli kanonik model:

```text
Hizmet Alanı / Service Domain
└── Hizmet Kategorisi / Service Category
    └── Hizmet / Service
        └── Hizmet Sunumu / Service Offering
            └── Katalog Öğesi veya Talep Tipi / Catalog Item or Request Type
```

Müşteri talep açarken kendi yetkisine göre uygun seçenekleri görmelidir.

Seçim aşağıdaki bilgileri otomatik belirleyebilmelidir:

- Dinamik form
- Zorunlu alanlar
- SLA
- Atanacak ekip
- Öncelik
- Onay akışı
- Fulfillment görev planı
- Çalışma takvimi
- Maliyet veya fiyat
- Bildirim şablonları
- Sözleşme ve entitlement
- Lokasyon veya departman uygunluğu

Kullanıcı yalnızca şu bağlama göre izin verilen kataloğu görmelidir:

- Tenant
- Organizasyon
- Departman
- Lokasyon
- Rol
- Sözleşme
- Entitlement
- Kullanıcı grubu

Mevcut kodda bazı yerlerde `service` kaydı “kategori” gibi kullanılmakta, CMDB tarafında ayrıca kategori kavramı bulunabilmektedir. Bu semantik çakışma ticari pilot öncesi çözülmelidir.

## 3.3 Raporlama

İlk ticari sürüm en az “özelleştirilebilir operasyonel raporlama” sunmalıdır.

Mevcut doğrulanan kapsam:

- Boyutlar: durum, hizmet, servis uzantısı/hizmet sunumu, talep tipi, ay
- Metrikler: talep sayısı, taahhüt sayısı, ihlal sayısı, SLA uyum oranı
- Tenant, tarih ve durum filtresi
- SQL allow-list
- CSV ve JSON dışa aktarım
- CSV formula injection koruması
- Private/shared kayıtlı raporlar

Henüz tamamlanmış kabul edilmemesi gereken gelişmiş raporlama özellikleri:

- Dinamik alanların rapora eklenmesi
- Hesaplanmış alan
- Pivot
- Drill-down
- Grafik tasarımcısı
- Zamanlanmış rapor
- E-posta teslimi
- Excel
- PDF
- Rol ve grup bazlı ayrıntılı paylaşım
- Kullanıcı tanımlı veri seti
- Dashboard widget tasarımcısı

Bu nedenle mevcut sürüm için doğru ifade:

> Özelleştirilebilir operasyonel raporlama

Yanlış veya erken ifade:

> Gelişmiş kurumsal BI platformu

## 3.4 Tenant ve MSP kullanımı

Temel hedef MSP ve çoklu organizasyon desteğidir.

İki dağıtım modeli korunmalıdır:

1. **Paylaşımlı uygulama / paylaşımlı şema**
2. **Müşteri başına ayrı deployment**

Shared-schema güvenliği bağımsız tenant kaçış testi tamamlanmadan tam güvenli olarak pazarlanmamalıdır.

Regüle müşteriler için ayrı deployment ticari paket olarak sunulabilir.

---

# 4. Mevcut mimari

## 4.1 Bugünkü mimari

İlk sürümlerde mikroservis dönüşümü yapılmamıştır.

```text
Müşteri Portalı / Agent UI / Admin UI
                  |
          Sürümlü API ve Web Katmanı
                  |
       CareOnCloud ESM tabanlı çekirdek + D724 paketleri
          |           |             |
       MariaDB     Redis Cache    Event/Outbox
          |                         |
    Elasticsearch              Worker/Webhook
```

Referans çalışma kümesi:

- Web ve daemon süreçleri
- MariaDB
- Redis
- Elasticsearch 8.19.3
- Docker Compose
- Cloudflare Tunnel

Kanonik CareOnCloud hedef adları:

- Uygulama yolu: `/careoncloud`
- Statik içerik: `/careoncloud-web`
- Kurulum dizini: `/opt/careoncloud`
- DB ve DB kullanıcısı: `careoncloud_esm`
- Şema: `careoncloud-schema.xml`
- İlk veri: `careoncloud-initial_insert.xml`

## 4.2 Uzun vadeli mimari hedef

CareOnCloud ESM kalıcı ürün markası veya nihai runtime hedefi değildir. Başlangıç ve geçiş çekirdeğidir.

Hedef yapı:

```text
CareOnCloud Portal / Agent UI / Admin UI
                      |
               CareOnCloud API
                      |
              CareOnCloud Domain
                      |
        ┌─────────────┴─────────────┐
        |                           |
   CareOnCloud ESM Adapter              Native Adapter
        |                           |
 Geçici CareOnCloud ESM Core          CareOnCloud Native Core
```

Yeni özellik geliştirme kuralı:

1. Önce CareOnCloud domain sözleşmesi tanımlanır.
2. CareOnCloud ESM erişimi adapter içinde yapılır.
3. Ürün modülü yalnızca CareOnCloud sözleşmesine bağımlı olur.
4. CareOnCloud ESM tablosuna veya iç API'sine doğrudan erişim istisnadır.
5. Her doğrudan bağımlılık için ADR ve kaldırma planı hazırlanır.
6. Zamanla `CareOnCloudAdapter`, `NativeAdapter` ile değiştirilir.

Ayrışma sırası:

1. Yeni müşteri portalı
2. Yeni agent arayüzü
3. Yeni admin arayüzü
4. CareOnCloud API sözleşmeleri
5. Katalog ve raporlama
6. Tenant ve identity policy
7. Workflow, approval ve SLA
8. Search ve knowledge
9. Ticket/case
10. E-posta işleme
11. CareOnCloud ESM DB ve runtime bağımlılığının kaldırılması

Ticket ve e-posta en sona bırakılmalıdır; CareOnCloud ESM'nun en olgun ve karmaşık alanlarıdır.

---

# 5. Mevcut modüller ve gerçekçi durumları

Aşağıdaki paketler kaynak snapshot'ında bulunmaktadır.

| Modül | Mevcut seviye | Ticari değerlendirme |
|---|---|---|
| `D724Foundation` | Çalışır temel paket, sağlık ve tanılama | Temel tamam; release doğrulaması gerekli |
| `D724TenantDirectory` | Tenant ve rol üyeliği altyapısı | MVP çekirdeği mevcut |
| `D724TenantGuard` | Varsayılan-ret tenant/RBAC politikası | Gerçek çekirdek; tam ABAC ve bütün yollar eksik |
| `D724Catalog` | Hizmet, offering, katalog öğesi, form ve portal/admin ekranları | Güçlü MVP; veri terminolojisi sabitlenmeli |
| `D724Request` | Request, onay, fulfillment durum makinesi | Gerçek çekirdek; uçtan uca rollback kanıtı gerekli |
| `D724Commitment` | SLA/OLA, takvim, pause/resume, warning/breach | Gerçek çekirdek; operasyon UX ve audit genişlemeli |
| `D724Audit` | Normalize olaylar, SHA-256 zinciri, export | Kurcalama tespiti sağlar; WORM değildir |
| `D724TicketAudit` | Bazı çekirdek ticket işlemlerinde audit ve tenant policy | Kısmi; önemli adapter'lar eksik |
| `D724Reporting` | Boyut/metrik seçimi, kayıtlı rapor, CSV/JSON | Kullanılabilir operasyonel raporlama MVP'si |
| `D724API` | `/api/v1`, client credentials, digest token, rate limit | Gerçek API temeli; transaction sorunu düzeltilmeli |
| `D724Webhook` | HMAC, retry, dead-letter, lifecycle olayları | Gerçek çekirdek; operasyon araçları genişlemeli |
| `D724Identity` | OIDC state/nonce, PKCE, agent/customer adapter | Kod temeli var; gerçek dış IdP testi şart |
| `D724SCIM` | User/group CRUD, ETag, If-Match, role reconciliation | İyi prototip; gerçek sağlayıcı testi gerekli |
| `D724Observability` | Prometheus health ve metrik endpoint'i | Temel tamam; alarm, trace ve runbook eksik |
| `D724CMDB` | Temel CI/asset/portfolio modeli ve import | Prototip; discovery ve reconciliation yok |
| `D724Problem` | İlk paket, agent ekranı, demo | Prototip; ticari modül sayılmaz |
| `D724Change` | İlk paket ve agent ekranı | Prototip; CAB/risk/uygulama deneyimi eksik |
| `D724Assist` | İnsan onaylı yardımcı çerçeve | AI ürünü değildir; başlangıç prototipi |

## 5.1 “Tamamlandı” sayılabilecek çekirdekler

Aşağıdakiler gerçek kod tabanına sahip ve MVP seviyesinde ilerlemiştir:

- Tenant Directory
- Tenant Guard temel politikası
- Hizmet kataloğu
- Request durum makinesi
- SLA/OLA commitment
- Audit çekirdeği
- Operasyonel reporting
- REST API temeli
- Webhook çekirdeği
- SCIM/OIDC temeli
- Prometheus endpoint

Bunlar yine de “production ready” değildir.

## 5.2 Kısmen hazır alanlar

- TicketAudit kapsamı
- Bütün tenant yolları
- Tam audit atomikliği
- OIDC uçtan uca
- SCIM gerçek sağlayıcı
- Marka temizliği
- Türkçe/İngilizce bütün ürün
- Deployment cutover
- CMDB
- Problem
- Change
- Assist

## 5.3 Yalnızca tasarım veya gelecek kapsamı

- Tam gelişmiş BI raporlama
- Major incident
- Tam knowledge deneyimi
- Contract/entitlement olgunluğu
- Gerçek AI gateway
- PII maskeli model orchestration
- HA/DR kanıtı
- Kurulum/upgrade sihirbazı
- OpenTelemetry tam dağıtımı
- Native CareOnCloud ticket core
- CareOnCloud ESM runtime bağımsızlığı

---

# 6. Kanıt seviyeleri

Her durum kaydı şu etiketlerden biriyle işaretlenmelidir:

## `VERIFIED_IN_CODE`

Kaynak kodda ilgili uygulama açıkça görüldü.

## `TEST_EXISTS_NOT_RERUN`

İlgili test dosyası veya kabul scripti var; fakat güncel snapshot üzerinde bağımsız olarak yeniden çalıştırılmadı.

## `VERIFIED_BY_CURRENT_TEST`

Test güncel commit/snapshot üzerinde çalıştı ve log/artifact mevcut.

## `DOCUMENT_CLAIM_ONLY`

Yalnızca dokümanda iddia ediliyor; kod veya güncel test sonucu bulunamadı.

## `PARTIAL`

Kodun bir bölümü gerçek; ticari olarak tamamlanması gereken açık alanlar var.

Bir AI, `TEST_EXISTS_NOT_RERUN` olan özelliği “başarıyla test edildi” diye raporlamamalıdır.

---

# 7. Doğrulanmış veya bilinen kritik riskler

## 7.1 API transaction sahipliği — P0

`D724API` içindeki transaction yönetiminde, modülün kendisine ait olmayan üst transaction'ı commit veya rollback etme riski bulunmuştur.

Kural:

- `BeginWork()` yalnızca fonksiyon kendi transaction'ını açacaksa çağrılır.
- `Commit()` ve `Rollback()` yalnızca aynı fonksiyon transaction'ın sahibiyse yapılır.
- İç içe transaction senaryosu test edilmelidir.

Örnek güvenli yaklaşım:

```perl
my $OwnTransaction = $Handle->{AutoCommit} ? 1 : 0;

if ($OwnTransaction) {
    $DBObject->BeginWork();
}

# business operation

if ($OwnTransaction) {
    $DBObject->Commit();
}
```

Rollback de yalnızca `$OwnTransaction` doğruysa yapılmalıdır.

Özellikle kontrol edilmesi gereken alanlar:

- `APIAuth.pm`
- API token oluşturma ve iptal
- Retention cleanup
- Audit atomikliği
- Üst request transaction'ları

## 7.2 Shared-schema tenant izolasyonu — P0

TenantGuard iyi bir başlangıçtır; fakat inherited CareOnCloud ESM çekirdeğinin bütün yollarını otomatik olarak güvenli yapmaz.

Özellikle envanterlenmesi ve negatif test edilmesi gereken yollar:

- Ticket create/read/update/delete
- Ticket merge
- Type
- Service
- SLA
- Pending
- Article
- Chat article
- Attachment
- Search
- Elasticsearch
- Export
- Notification
- Generic Interface
- Scheduler
- Daemon
- Cache
- Reporting
- Package/admin operasyonları
- Webhook
- API
- Background worker

Bir tek eksik yol cross-tenant veri sızıntısına dönüşebilir.

## 7.3 Audit tanımı — P0

SHA-256 zinciri audit kayıtlarının değiştirildiğini tespit etmeye yardımcı olur.

Bu, tek başına:

- WORM
- Donanımsal değiştirilemezlik
- Hukuken immutable log

değildir.

Doğru ürün ifadesi:

> Zincirlenmiş ve kurcalama tespitine yardımcı audit izi

Gerçek değiştirilemezlik için:

- Harici imzalama
- Object Lock
- WORM storage
- Ayrı güvenilir log hedefi
- Zaman damgası veya imza zinciri

gerekir.

## 7.4 TicketAudit kapsamı — P0

Eksik olduğu bilinen veya yeniden doğrulanması gereken alanlar:

- Delete
- Merge
- Type değişimi
- Service değişimi
- SLA değişimi
- Pending
- Chat article
- Bazı Generic Interface yolları
- Scheduler/daemon yazımları

İş mutasyonu ile audit olayının aynı transaction veya güvenilir outbox garantisi içinde olması gerekir.

## 7.5 Yanlış SECURITY.md — P0

Root `SECURITY.md` upstream CareOnCloud ESM politikasından kalmış olabilir ve fork'ları kapsam dışı bırakabilir.

CareOnCloud için ayrı politika gereklidir:

- Desteklenen sürümler
- Security contact
- İlk yanıt süresi
- Kritik düzeltme hedefi
- CVE süreci
- Managed müşteri bildirimi
- Güvenli araştırma kapsamı
- Test sistemleri
- Üretim sistemleri
- Disclosure süreci

## 7.6 CI kapsamı — P0

CI bütün `D724*` paketlerini kapsamalıdır.

Zorunlu kapılar:

- SOPM/XML parse
- Perl syntax ve code policy
- Unit test
- MariaDB entegrasyon testi
- Tenant negatif testleri
- API contract testleri
- Package install
- Package upgrade
- Package uninstall veya geri alma
- Türkçe/İngilizce testleri
- Runtime marka taraması
- Docker build
- Dependency scan
- Secret scan
- SBOM
- İmzalı release

Upstream CareOnCloud ESM image, repository veya Dockerfile adlarına bağlı eski workflow'lar temizlenmelidir.

## 7.7 Marka kalıntıları — P0

Kaynak kod içinde yasal CareOnCloud ESM referanslarının kalması normaldir.

Ancak kullanıcıya görünen alanlar ayrıca taranmalıdır:

- Installer
- Support collector
- Package manager
- Mobil uyarılar
- Yardım bağlantıları
- E-posta metinleri
- HTML title
- Cookie
- Header
- URL
- Log
- DB
- Volume
- Container
- Systemd unit
- Nginx
- PSGI/Plack
- CLI output

Allow-list yaklaşımı kullanılmalıdır:

- README
- NOTICE
- UPSTREAM.md
- LICENSE
- Kaynak telifleri

dışındaki kullanıcı görünür CareOnCloud ESM referansları hata sayılmalıdır.

## 7.8 Lisans metadata tutarlılığı — P0

Kontrol edilmesi gereken olası tutarsızlıklar:

- `GPL-3.0-only`
- `GPL-3.0-or-later`
- README
- LICENSE
- SPDX
- SOPM metadata
- Container label
- Release belgesi
- Eksik veya yanlış `COPYING` bağlantısı

Tek lisans politikası belirlenmeli ve bütün dosyalarda aynı uygulanmalıdır.

## 7.9 Türkçe/İngilizce bütünlüğü — P0

Türkçe desteği bazı paketlerde daha güçlüdür; bütün ürün için tamamlanmış sayılmamalıdır.

Kontrol:

- Portal
- Agent
- Admin
- Request
- Commitment
- Reporting
- Problem
- Change
- CMDB
- Identity
- SCIM
- API hata metinleri
- E-posta
- Demo
- Installer

Mojibake ve encoding taraması yapılmalıdır.

---

# 8. Test ve çalışma ortamı durumu

## 8.1 Kaynak snapshot

Teslim edilen kaynak paketinin adı:

- `CareOnCloud-ESM-source-5cba3fe.zip`

Doküman paketi:

- `CareOnCloud-ESM-handoff-docs-5cba3fe.zip`

`5cba3fe` snapshot/commit göstergesi olabilir; gerçek Git commit, branch ve dirty durum Git üzerinden doğrulanmalıdır.

Snapshot içinde `.git` yoksa şunlar bağımsız doğrulanamaz:

- Commit geçmişi
- Branch
- Uncommitted diff
- Tag
- Signed commit
- Remote
- Upstream sync

## 8.2 Test sunucusu

Referans test ortamı:

- Özel sunucu: `100.86.171.110`
- Dış adres: `https://esm.arcak.net/`
- Yeni kaynak alanı: `/home/test/careoncloud-releases/20260725`

Secret ve parola bu dosyada saklanmaz.

2 Ağustos 2026 tarihli devir bilgisinde:

- Dış adres HTTP 200 dönüyordu.
- Canlı web/daemon eski çalışma kümesi olabilirdi.
- Yeni image: `d724/esm:dev`
- Yeni `careoncloud_esm` DB hazırlanmıştı.
- Yeni CareOnCloud volume'ları oluşturulmuştu.
- Eski DB/image/volume rollback için korunuyordu.
- Mavi/yeşil aday doğrulaması tamamlanmamıştı.
- `/careoncloud/index.pl` kabulü tamamlanmamıştı.
- Paket upgrade/install kontrolü tamamlanmamıştı.
- Nihai port kesimi yapılmamıştı.

Bu bilgi güncel kabul edilmemeli; işlem öncesi yeniden doğrulanmalıdır.

## 8.3 Güvenli cutover sırası

1. Mevcut origin ve dış adres sağlığını doğrula.
2. Eski DB/image/volume için doğrulanmış rollback kaydı oluştur.
3. Yeni image'ı farklı container adı ve alternatif portta başlat.
4. Yeni CareOnCloud DB ve volume'larını kullan.
5. `/careoncloud/index.pl`, health, login, statik dosya, cookie ve header'ı test et.
6. D724 paket install/upgrade durumunu doğrula.
7. Katalog, request, reporting ve tenant kısa kabul paketini çalıştır.
8. Runtime marka taraması yap.
9. Backup/restore kontrolünü doğrula.
10. Yalnızca bütün P0 testleri geçerse bakım penceresinde port kesimi yap.
11. Sorunda eski kümeye dön.
12. Kabul süresi dolmadan eski DB/image/volume'ları silme.

---

# 9. Revize edilmiş ana goal

## CAREONCLOUD ESM — COMMERCIAL PILOT STABILIZATION GOAL

### Amaç

Mevcut CareOnCloud ESM geliştirme prototipini yeni özelliklerle genişletmek yerine:

- Güvenli
- Tekrarlanabilir
- İki dilli
- Güncellenebilir
- Geri alınabilir
- Ticari pilotta kullanılabilir

bir GPL-3.0 release haline getir.

### Koruma kuralları

- Mevcut kaynak kodu ve veriyi koru.
- Toplu reset veya yeniden yazım yapma.
- Önce current state snapshot ve Git tag oluştur.
- Her DB veya deployment değişikliği için rollback yöntemi oluştur.
- Secret'ları repository veya dokümana ekleme.
- Kanıtsız “done” durumu üretme.

### CareOnCloud ESM politikası

- Köken README, NOTICE, telif ve GitHub'da kalır.
- Son kullanıcı arayüzünde CareOnCloud ESM görünmez.
- CareOnCloud ESM geçiş çekirdeğidir.
- Yeni kod CareOnCloud domain/interface üzerinden yazılır.
- Doğrudan CareOnCloud ESM bağımlılığı ADR ve kaldırma sürümü taşır.
- GPL-3.0 korunur.

### Öncelik sırası

1. Kaynak ve test baz çizgisini oluştur.
2. API transaction sahipliği hatalarını düzelt.
3. Tenant erişim envanteri çıkar ve negatif testleri tamamla.
4. TicketAudit ve atomik audit/outbox kapsamını tamamla.
5. Katalog veri modelini sabitle.
6. CI ve package lifecycle testlerini tamamla.
7. Backup/restore, upgrade ve rollback provası yap.
8. Runtime marka temizliğini tamamla.
9. Türkçe/İngilizce kritik yolculukları tamamla.
10. GPL metadata ve security policy'yi düzelt.
11. Mavi/yeşil aday release'i doğrula.
12. Pilot kapıları karşılanmadan canlı kesim veya üretim iddiası yapma.

### Bu fazda dondurulacak alanlar

Kritik hata dışında yeni özellik geliştirme:

- Problem
- Change
- CMDB genişlemesi
- Major Incident
- Assist/AI
- Yeni ESM modülü
- Yeni mikroservis dönüşümü

başlatılmamalıdır.

---

# 10. Önceliklendirilmiş ürün planı

## P0.1 — Kaynak baz çizgisi

Çıktılar:

- Kanonik repository
- Aktif branch
- HEAD SHA
- Temiz veya açıklanmış çalışma ağacı
- Snapshot tag
- Source artifact
- Docker image digest
- Paket sürüm listesi
- Test sonucu artifact'ları
- Release notes

Komut çıktıları saklanmalı:

```bash
git status --short
git branch --show-current
git rev-parse HEAD
git remote -v
git log --oneline --decorate -30
git diff --stat
git diff --name-status
git diff --check
```

## P0.2 — Güvenlik ve veri bütünlüğü

- API transaction sahipliği
- Tenant path inventory
- Cross-tenant negative test matrix
- TicketAudit eksikleri
- Audit/outbox atomikliği
- Secret scan
- Dependency scan
- CareOnCloud SECURITY.md
- Pentest hazırlığı
- Dedicated deployment seçeneği

## P0.3 — Katalog modeli

Kanonik model kararı:

```text
Service Domain
→ Service Category
→ Service
→ Service Offering
→ Catalog Item / Request Type
```

Yapılacaklar:

- Mevcut tabloları semantik olarak eşleştir.
- CMDB ve Catalog kategori modelini birleştir.
- Türkçe/İngilizce kanonik terim sözlüğü oluştur.
- Mevcut 6 alan ve 51 offering'i migrate et.
- Katalog/form şeması için sürümleme ekle.
- Eski request'in bağlı olduğu katalog sürümünü koru.
- Draft/published/retired lifecycle ekle.

## P0.4 — Release ve operasyon

- D724 CI matrisi
- Install/upgrade/uninstall
- Backup/restore
- RPO/RTO ölçümü
- Rollback provası
- Mavi/yeşil doğrulama
- SBOM
- İmzalı artifact
- Reproducible build
- Deployment runbook
- Operasyon dashboard'u
- Uzun süreli daemon testi

## P0.5 — Marka, dil ve GPL

- Runtime CareOnCloud ESM allow-list taraması
- TR/EN portal kabulü
- TR/EN agent kabulü
- UTF-8/mojibake taraması
- LICENSE/SPDX normalize
- README/NOTICE/UPSTREAM
- CareOnCloud SECURITY.md
- Kullanıcı ve yönetici dokümanları

## P1 — Kontrollü pilot

Yalnızca P0 kapıları geçerse:

- 1–3 tasarım ortağı
- 90 günlük pilot
- Müşteri başına ayrı deployment varsayılanı veya açık risk kabulü
- Gerçek hacim ve SLA ölçümü
- Gerçek OIDC
- Gerçek SCIM
- Scheduled reporting
- Excel/PDF
- Kullanıcı deneyimi düzeltmeleri
- Kurulum ve operasyon dokümanı

## P2 — Ürün olgunlaştırma

- Problem
- Change/CAB
- Major Incident
- Knowledge
- CMDB reconciliation ve impact
- Contract/entitlement
- Gelişmiş rapor tasarımcısı
- HA/DR
- OpenTelemetry
- Upgrade sihirbazı

## P3 — CareOnCloud ESM teknik ayrışması

- Yeni UI
- Native CareOnCloud domain
- Adapter dönüşümü
- Native workflow/SLA
- Native ticket/case
- Native e-posta
- CareOnCloud ESM runtime kaldırılması

GPL ve köken atfı devam eder.

---

# 11. Definition of Done

Bir özellik ancak aşağıdaki şartların tümü karşılanırsa tamamlanmış sayılır:

1. Kod mevcut ve review edilmiştir.
2. Türkçe ve İngilizce kritik akış çalışır.
3. Tenant/rol negatif testleri vardır.
4. Unit test geçer.
5. Entegrasyon testi geçer.
6. MariaDB veya ilgili gerçek backend kabulü geçer.
7. Audit olayı doğrulanır.
8. Başarısızlıkta rollback davranışı doğrulanır.
9. Migration belgelenmiştir.
10. Geri dönüş yöntemi belgelenmiştir.
11. Paket temiz kurulabilir.
12. Paket upgrade edilebilir.
13. CI'da yeniden üretilebilir.
14. Kullanıcı dokümantasyonu vardır.
15. Operasyon dokümantasyonu vardır.
16. İlgili CareOnCloud ESM bağımlılığı kaydedilmiştir.
17. Güvenlik ve veri sızıntısı testi geçmiştir.
18. Test sonucu artifact olarak saklanmıştır.

---

# 12. Ticari pilot çıkış kapıları

Pilot başlamadan önce:

- Tam regresyon yeşil
- Bilinen P0 güvenlik açığı yok
- Cross-tenant test matrisi yeşil
- TicketAudit kritik yolları tamam
- Audit iddiaları doğru terminolojiyle sunuluyor
- Gerçek OIDC login/logout tamam
- SCIM kritik lifecycle testleri tamam
- Backup/restore doğrulanmış
- Upgrade/rollback doğrulanmış
- Clean install başarılı
- Existing data upgrade başarılı
- Runtime marka taraması temiz
- TR/EN uçtan uca kabul tamam
- SBOM mevcut
- Release artifact imzalı
- Docker image commit ile eşleşiyor
- Security policy yayımlanmış
- Dedicated deployment kurulumu belgelenmiş
- Pentest veya en azından bağımsız güvenlik değerlendirmesi tamamlanmış

Bu kapılar karşılanmadan şu ifadeler kullanılmamalıdır:

- Production ready
- Tam tenant izolasyonu
- Değiştirilemez audit
- ServiceNow'un tam alternatifi
- Tam iki dilli ürün
- Enterprise-ready HA/DR

---

# 13. AI çalışma biçimi

Bu projeye yeni katılan AI aşağıdaki sırayı izlemelidir.

## 13.1 İlk değerlendirme

1. Bu dosyayı oku.
2. `AI-DEGERLENDIRME-DEVIR-DOKUMANI.md` varsa oku.
3. `STATUS.md`, `ARCHITECTURE.md`, `PRODUCT.md`, `ROADMAP.md` dosyalarını oku.
4. Kaynak ZIP varsa modülleri koddan doğrula.
5. Git repository erişimi varsa Git durumunu doğrula.
6. Test çıktısı yoksa geçmiş PASS iddiasını güncel kabul etme.
7. Önce risk ve bağımlılık haritası çıkar.
8. Yıkıcı değişiklik yapmadan plan öner.

## 13.2 Kod değişikliği öncesi

- Aktif branch
- HEAD SHA
- Dirty files
- DB durumu
- Container durumu
- Backup durumu
- Geri dönüş planı

kontrol edilmelidir.

## 13.3 Raporlama biçimi

Her maddeyi şu statülerden biriyle raporla:

- `DONE_AND_VERIFIED`
- `CODE_PRESENT_TEST_NOT_RERUN`
- `PARTIAL`
- `DESIGN_ONLY`
- `BLOCKED`
- `RISK`
- `NOT_FOUND`

## 13.4 Yasak davranışlar

- Özellik varmış gibi uydurmak
- Test çalıştırmadan “test geçti” demek
- Toplu reset
- Secret yazmak
- Canlı DB'de doğrudan deneme
- CareOnCloud ESM telifini silmek
- CareOnCloud ESM kökenini gizlemek
- Kullanıcı görünür CareOnCloud ESM markasını bırakmak
- Yeni özellik ekleyerek P0 riskleri ertelemek
- Gerçek şirketleri izinsiz demo müşterisi gibi göstermek

Demo verileri sentetik olmalıdır.

---

# 14. Projeyle birlikte verilmesi faydalı dosyalar

Bu ana bağlam dosyası ürünün bütün amacını anlamaya yeterlidir. Ancak kod düzeyinde çalışma için aşağıdaki dosyalar da eklenmelidir:

- `CareOnCloud-ESM-source-5cba3fe.zip`
- `CareOnCloud-ESM-handoff-docs-5cba3fe.zip`
- Güncel `git-status.txt`
- Güncel `git-diff-stat.txt`
- Güncel test logları
- Güncel Docker build logu
- Package install/upgrade logu
- Secret içermeyen deployment config
- Güncel DB schema ve migration'lar

Ana referans belgeler:

- `AI-DEGERLENDIRME-DEVIR-DOKUMANI.md`
- `STATUS.md`
- `PRODUCT.md`
- `ARCHITECTURE.md`
- `ROADMAP.md`
- `GPL-COMMERCIAL.md`
- `BRAND-01.md`
- `SHOWCASE.md`
- `NOTICE`
- `SECURITY.md`
- `UPSTREAM.md`
- `CareOnCloud ESM-DEPENDENCY-REGISTER.md`

---

# 15. Yeni bir ChatGPT oturumunda kullanılacak başlangıç talimatı

Bu dosya bir ChatGPT Project'e veya özel GPT'nin Knowledge bölümüne yüklendikten sonra yeni konuşma şu talimatla başlatılabilir:

> CareOnCloud ESM AI Master Context dosyasını eksiksiz oku ve bu projedeki bütün kararlarında ana kaynak olarak kullan. Kaynak kod paketi de mevcutsa dokümandaki iddiaları kod ve testler üzerinden doğrula. Önce mevcut durumu DONE_AND_VERIFIED, CODE_PRESENT_TEST_NOT_RERUN, PARTIAL, DESIGN_ONLY, BLOCKED ve RISK olarak sınıflandır. Yeni özellik geliştirmeden önce P0 güvenlik, test, release, marka, iki dil ve rollback eksiklerini önceliklendir. Toplu reset veya yeniden yazım yapma. OTOBO kökenini GitHub ve lisans alanlarında koru; son kullanıcı deneyiminde OTOBO markası bırakma. GPL-3.0 korunacaktır.

---

# 16. Bir cümlelik proje özeti

> CareOnCloud ESM, OTOBO'nun GPL-3.0 kod tabanından fork edilerek başlatılmış; Türkçe/İngilizce hizmet kataloğu, request orchestration, SLA, tenant kontrollü MSP kullanımı, audit, reporting ve açık API üzerine odaklanan; OTOBO kökenini yasal olarak korurken kullanıcı deneyimi ve zamanla runtime bakımından bağımsızlaşmayı hedefleyen bir ESM ürünüdür.

---

# 17. Son karar

CareOnCloud ESM'nin en önemli sonraki işi yeni modül sayısını artırmak değildir.

Öncelik:

1. Mevcut kaynak durumunu sabitlemek
2. Güvenlik ve tenant sınırını kanıtlamak
3. Audit kapsamını tamamlamak
4. Katalog modelini sabitlemek
5. Test ve CI'ı yeniden üretilebilir yapmak
6. Backup, upgrade ve rollback'i kanıtlamak
7. Marka ve iki dil temizliğini tamamlamak
8. İmzalı ve desteklenebilir ticari pilot release üretmek

olmalıdır.

Bu tamamlandıktan sonra ürün kontrollü pilotla gerçek müşteri kullanımına açılabilir.
