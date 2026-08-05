# CareOnCloud ESM — Yapay Zekâ Değerlendirme ve Teknik Devir Dokümanı

**Belge tarihi:** 2 Ağustos 2026

**Belgenin amacı:** Başka bir yapay zekânın veya teknik ekibin projeyi önceki konuşmalara ihtiyaç duymadan değerlendirebilmesi.

**Durum etiketi:** Geliştirme prototipi / ticari ürün adayı; üretim sürümü değildir.

## 1. Yönetici özeti

CareOnCloud ESM; ServiceNow ve 4me sınıfındaki temel Enterprise Service Management ihtiyaçlarını, daha yalın kurulum, açık veri modeli, MSP/multi-tenant kullanım ve Türkçe deneyim odağıyla karşılamayı amaçlayan GPL-3.0 bir ürün çalışmasıdır.

Proje, `RotherOSS/otobo` deposunun `rel-11_1` tabanından türetilmiştir. Kaynak kökeni, telif ve GPL bildirimleri korunur. OTOBO adı son kullanıcı ürünü, arayüz, çalışma yolları, veritabanı ve altyapı markası olarak kullanılmamalıdır; köken bilgisi yalnızca GitHub README/NOTICE ve hukuken gerekli kaynak bildirimlerinde kalmalıdır. Ticari ürün adı **CareOnCloud ESM**, sloganı **“Hizmet Bulutta, Kontrol Sizde.”** olarak belirlenmiştir.

Bugüne kadar multi-tenant güvenlik çekirdeği, hizmet kataloğu, talep/onay/fulfillment akışı, SLA/OLA taahhütleri, audit, API, webhook, OIDC/SCIM temeli, raporlama, gözlemlenebilirlik, CMDB/servis portföyü, problem ve change için modüler bir yapı oluşturuldu. Önemli bölümlerde otomatik ve gerçek MariaDB kabul testleri bulunuyor. Bununla birlikte ürün henüz ticari `1.0` değildir; marka geçişinin canlı kesimi, bütünleşik kullanıcı deneyimi, tam audit kapsamı, gerçek dış IdP kabulü, üretim sertleştirmesi, yedek/geri dönüş tatbikatı, SBOM/imzalı yayın ve bağımsız güvenlik testi tamamlanmalıdır.

## 2. Ürün hedefi ve konumlandırma

### Ana hedef

- ITSM ile sınırlı kalmayan; IT, İK, tesis, perakende operasyonu ve yönetilen hizmet taleplerini tek katalogda toplamak.
- Hizmet alanın talep açarken **hizmet kategorisi → servis uzantısı/hizmet sunumu → talep tipi** hiyerarşisini seçebilmesi.
- Agent, hizmet sahibi, platform yöneticisi, MSP yöneticisi ve denetçi için rol ve tenant sınırları olan tek çalışma yüzeyi sağlamak.
- Durum, hizmet, servis uzantısı, talep tipi ve ay gibi boyutlarla özelleştirilebilir raporlar; talep, taahhüt, ihlal ve SLA uyum metrikleri sunmak.
- Türkçe ve İngilizce çekirdek ürün deneyimi sunmak.
- Açık API, dışarı aktarılabilir veri ve denetlenebilir otomasyon sağlamak.
- Gelecekte PII korumalı ve insan onaylı yapay zekâ özellikleri eklemek.

### Hedef kullanıcılar

- Hizmet alan/müşteri: katalogdan talep açar, durum ve taahhütleri görür.
- Agent/uzman: kuyruk, görev, bilgi, CI/varlık ve SLA bağlamında çalışır.
- Hizmet sahibi: katalog, maliyet, kapasite, SLA/OLA ve iyileştirme verisini yönetir.
- Platform yöneticisi: tenant, kimlik, yetki, entegrasyon ve otomasyonu kurar.
- MSP yöneticisi: çok müşterili ortamda sözleşme ve veri sınırlarını yönetir.
- Denetçi: değiştirilemez olay izi ve kanıt dışa aktarımını inceler.

### Önerilen ticari model

GPL kodunu kapatmak yerine gelir; onaylı build, kurulum, upgrade, entegrasyon, destek, HA/DR, uyum ve yönetilen hizmetten üretilmelidir:

- Community: kaynak kod ve topluluk dokümantasyonu.
- Professional: onaylı build, upgrade ve iş saatleri desteği.
- Enterprise: SSO/SCIM, HA/DR, 7×24 destek ve uyum paketi.
- Managed: barındırma, izleme, yedekleme, güncelleme ve operasyon SLA'sı.

Bu yaklaşım hukuki görüş değildir; ilk ticari dağıtımdan önce açık kaynak ve marka hukuku incelemesi gereklidir.

## 3. Mimari yaklaşım

İlk sürümlerde mikroservis dönüşümü yapılmamıştır. Türetilen çekirdek; ticket/workflow, zamanlama, kimlik, paket yönetimi, Generic Interface ve arama için sistem-of-record olarak kalır. Yeni kabiliyetler `CareOnCloud*` adlı GPL-3.0 paketler şeklinde eklenmiştir.

```text
Müşteri Portalı / Agent UI / Admin UI
                  |
          Sürümlü API ve Web Katmanı
                  |
       CareOnCloud çekirdeği + CareOnCloud paketleri
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
- Dış erişim için Cloudflare Tunnel

Hedef kanonik adlar:

- Ürün: `CareOnCloud ESM`
- Uygulama yolu: `/careoncloud`
- Statik içerik yolu: `/careoncloud-web`
- Kurulum dizini: `/opt/careoncloud`
- Veritabanı ve DB kullanıcısı: `careoncloud_esm`
- Şema dosyaları: `careoncloud-schema.xml`, `careoncloud-initial_insert.xml`

## 4. Geliştirilen modüller

| Modül | Amaç | Mevcut durumun özeti |
|---|---|---|
| `CareOnCloudFoundation` | Ürün/edition ayarları, temel sağlık ve paket doğrulama | Çalışır temel paket ve tanılama komutları |
| `CareOnCloudTenantDirectory` | Tenant ve kullanıcı/rol üyelikleri | Kalıcı directory, bootstrap, üyelik verme/geri alma |
| `CareOnCloudTenantGuard` | Merkezi tenant ve rol politikası | Varsayılan-ret, cross-tenant engeli, report/search/cache/automation aksiyonları |
| `CareOnCloudCatalog` | Hizmet, sunum/uzantı, katalog öğesi ve dinamik form | Müşteri ve yönetici ekranları; kategori → uzantı → talep tipi doğrulaması; Türkçe metinler |
| `CareOnCloudRequest` | Talep, onay ve fulfillment durum makinesi | İdempotent oluşturma, optimistic version, agent/müşteri akışı, katalog bağlam doğrulaması |
| `CareOnCloudCommitment` | SLA/OLA hedefleri ve eskalasyon | Takvim, pause/resume, warning/breach, dispatcher, retry/dead-letter |
| `CareOnCloudAudit` | Normalize ve eklemeli audit olayları | SHA-256 zinciri, cursor/NDJSON export ve bazı domainlerde atomik yazım |
| `CareOnCloudTicketAudit` | Çekirdek ticket işlemlerini audit ve tenant politikasına bağlama | Ticket create ve temel alan/article işlemlerinde kapsam; kalan adapterlar var |
| `CareOnCloudReporting` | Operasyon ve özelleştirilebilir raporlar | Boyut/metrik seçimi, CSV/JSON, private/shared kayıtlı raporlar, tenant/date/status doğrulaması, Türkçe UI |
| `CareOnCloudAPI` | `/api/v1` REST sözleşmesi | Client credentials, digest token, rate limit, request read/create/lifecycle ve OpenAPI 3.1 |
| `CareOnCloudWebhook` | İmzalı olay teslimi | Abonelik CRUD, HMAC, retry/dead-letter ve lifecycle olayları |
| `CareOnCloudIdentity` | OIDC kimlik doğrulama | Issuer/audience route, state/nonce, PKCE S256 ve agent/customer adapter temeli |
| `CareOnCloudSCIM` | SCIM 2.0 kullanıcı/grup yaşam döngüsü | User/group CRUD, ETag/If-Match, rol uzlaştırma, tenant-safe HTTP yüzeyi |
| `CareOnCloudObservability` | Prometheus sağlık/metrikleri | Sabit etiketli, PII içermeyen metrikler ve Bearer korumalı endpoint |
| `CareOnCloudCMDB` | CI/varlık ve servis portföyü bağlamı | Temel model, workbook import ve portföy görünümü |
| `CareOnCloudProblem` | Problem yönetimi | İlk paket, agent ekranı ve demo verisi; olgunlaştırılmalı |
| `CareOnCloudChange` | Change enablement | İlk paket ve agent ekranı; CAB/risk/uygulama deneyimi tamamlanmalı |
| `CareOnCloudAssist` | İnsan onaylı yardımcı yetenekleri için çerçeve | Başlangıç paketi; üretim AI gateway'i değildir |

Paketler birbirlerinin tablolarına doğrudan yazmak yerine yayınlanan Perl API'leri ve sözleşmeleri kullanma hedefi taşır. Dış isteklerde tenant bağlamı, yetki, idempotency ve audit temel kalite kapılarıdır.

## 5. Özellikle tamamlanan ürün talepleri

### Hizmet kataloğu

- Verilen DORA uyumlu Careon hizmet kataloğu dokümanından 6 ana alan ve 51 yönetilen hizmet sunumu modellenmiştir.
- Müşteri talebinde kategori, servis uzantısı/hizmet sunumu ve talep tipi seçimi eklenmiştir.
- Seçim hiyerarşisi sunucu tarafında doğrulanır; değiştirilmiş/tamper edilmiş parent-child kombinasyonları reddedilir.
- Yönetici katalog/form yönetimi ile müşteri katalog görüntüleme akışları vardır.

### Özelleştirilebilir raporlama

- Boyutlar: durum, hizmet, servis uzantısı, talep tipi, ay.
- Metrikler: talep sayısı, taahhüt sayısı, ihlal sayısı, SLA uyum oranı.
- Tenant, tarih ve durum filtreleri doğrulanır; SQL alanları allow-list üzerinden seçilir.
- CSV ve JSON dışa aktarım vardır; CSV formula injection koruması uygulanmıştır.
- Rapor tanımları private/shared olarak kaydedilebilir; sahiplik kontrollü listeleme, getirme, silme ve çalıştırma akışları vardır.
- Operasyon raporu katalog kapasitesi ile gerçekleşen kullanımı ayırır.

### Dil ve marka

- Çekirdek ürün hedefi Türkçe/İngilizce çalışmadır.
- Katalog ve raporlama için Türkçe dil modülleri eklenmiştir.
- Careon marka varlıkları agent, müşteri ve giriş ekranlarına eklenmiştir.
- Sağlanan Careon logosuna uyumlu PNG varlıkları bulunmaktadır.
- Eski ürün adını CLI, PSGI, Dockerfile, şema, Nginx, systemd, i18n, font ve çalışma yollarından kaldırmaya yönelik geniş bir yeniden adlandırma yapılmıştır.
- Kaynak kökeni `NOTICE` ve README içinde korunmalıdır; upstream telif satırları silinmemelidir.

### Demo

- Gerçek şirketlerin müşteri olduğu izlenimi verilmemesi için sentetik tenantlar kullanılmıştır: `Marmara Bank Demo`, `Anadolu Moda Demo`, `Perakende360 Demo`.
- Toplam 36 örnek request ve 99 commitment üretilmiştir.
- Durum dağılımı; tamamlanmış, onay bekleyen, fulfillment sürecindeki, reddedilmiş ve başarısız kayıtları içerir.
- Demo seed işlemleri idempotent tasarlanmıştır.
- Demo raporları JSON/CSV ve yönetici özeti şeklinde üretilebilir.
- Panço, LC Waikiki, Süvari veya İş Bankası gibi gerçek şirket adları müşteri/referans olarak kullanılmamıştır; bu etik ve hukuki sınır korunmalıdır.

## 6. Güvenlik ve veri sınırı

Temel tasarım paylaşımlı uygulama/paylaşımlı şemadır. Tenant kapsamlı tablolarda `tenant_id` zorunlu olmalı ve erişim merkezi policy katmanından geçmelidir.

Uygulanan başlıca kontroller:

- Varsayılan-ret rol/aksiyon matrisi.
- Exact ve case-sensitive tenant sınırı.
- Cross-tenant talepleri reddetme.
- Katalog, rapor, cache, arama, API, webhook ve bazı çekirdek ticket yollarında tenant policy.
- OIDC state/nonce ve PKCE S256.
- SCIM optimistic concurrency ve tenant kapsamı.
- API tokenlarının açık değerini değil digest'ini saklama.
- Audit olaylarında SHA-256 zinciri.
- Webhook HMAC, retry ve dead-letter.
- Rapor dışa aktarımında PII azaltma ve CSV formula koruması.
- Prometheus metriklerinde dinamik tenant/PII etiketi kullanmama.

Kalan kritik eksik: Generic Interface `TicketCreate` source-level request transaction/rollback regresyonuna sahiptir ancak candidate MariaDB kabulü bekler; GenericAgent ve diğer scheduler/daemon yazımları, non-MIME article backend'leri, harici eklenti/doğrudan DB yazımları ve index/storage gibi cross-system side effect'ler aynı transaction/outbox audit completeness garantisine sahip değildir. Bu nedenle “tam tenant izolasyonu ve tam değiştirilemez audit” iddiası bağımsız test olmadan yapılmamalıdır.

## 7. Test ve doğrulama kanıtı

Depoda paket bazlı Perl testleri, HTTP kabul scriptleri ve operasyon kontrol komutları vardır. Önceki çalışmalarda aşağıdakiler doğrulanmıştır:

- Paketlerin SOPM/XML parse ve Perl syntax kontrolleri.
- Katalog parent-child ve tamper reddi testleri.
- Request idempotency, optimistic concurrency ve hata sonrası retry.
- Audit yazımı başarısız olduğunda bazı request/catalog/directory mutasyonlarının rollback olması.
- İki paralel writer için audit dedupe.
- TicketSearch ve Elasticsearch üzerinde cross-tenant hit/miss izolasyonu.
- SCIM gerçek MariaDB kabulü.
- Prometheus endpoint için eksik/yanlış/doğru Bearer sonucunun `401/401/200` olması.
- Marka sözleşmesi testi ve `git diff --check`.
- Önceki aday denemelerinde CareOnCloud imajı oluşturulmuştu; mevcut test sunucusunda güncel kaynakla runtime imaj kabulü BuildKit-capable runner eksikliği nedeniyle yeniden kanıtlanmadı.

Mevcut çalışma ağacı bu devir güncellemesinde temizdir; yine de son marka geçişi sonrasında **tam test paketi yeniden çalıştırılmamıştır**. Eski tarihli test sayıları güncel çalışma ağacının nihai kanıtı sayılmamalıdır.

## 8. Canlı/test sunucusunun güncel durumu

**Sunucu:** özel test sunucusu `100.86.171.110`

**Dış adres:** `https://esm.arcak.net/`

**2 Ağustos 2026 son kontrol:** ana adres HTTP `200` döndürmektedir.

Önemli durum ayrımı:

1. Dış adres şu anda erişilebilirdir.
2. Hizmet veren `web` ve `daemon` konteynerleri eski çalışma kümesidir; arayüzde/eski URL ve header/cookie alanlarında eski marka kalıntıları olabilir.
3. Yeni CareOnCloud kaynak kopyası sunucuda `/home/test/careoncloud-releases/20260725` altındadır.
4. Güncel kaynak için yeni Docker imajı henüz kabul edilmemiştir: sunucuda `docker buildx` yoktur ve legacy builder Dockerfile heredoc bloklarını çalıştırmadığı için bu deneme runtime kanıtı sayılmaz.
5. Önceki aday hazırlığında yeni `careoncloud_esm` veritabanına 175 tablo kopyalanmış ve yeni CareOnCloud app/update volume'ları oluşturulmuştur; bu tarihsel hazırlık güncel runtime kabulü değildir.
6. Eski veritabanı, volume ve imajlar geri dönüş için silinmemiştir.
7. **Mavi/yeşil aday çalıştırma, `/careoncloud/index.pl` kabulü, paket upgrade/install kontrolü ve nihai port kesimi henüz yapılmamıştır.**

Bu nedenle marka/veri geçişi “hazırlandı fakat canlı kesim tamamlanmadı” şeklinde değerlendirilmelidir. Canlı sistemi kapatmadan önce aday konteynerin alternatif portta doğrulanması gerekir.

## 9. Önerilen güvenli geçiş sırası

1. Mevcut `esm.arcak.net` ve eski web/daemon sağlığını tekrar doğrula.
2. Yeni imajı farklı konteyner adı ve alternatif yerel portla, yeni CareOnCloud volume ve `careoncloud_esm` DB üzerinde başlat.
3. `/careoncloud/index.pl`, health, login, header/cookie ve statik varlıkları doğrula.
4. Kurulu CareOnCloud paket sürümlerini incele; gerekli paket build/upgrade işlemlerini aday üzerinde yap.
5. Katalog, request, raporlama, tenant izolasyonu ve demo için kısa kabul paketi çalıştır.
6. UI/API/header/cookie/DB/volume/yol taramasında eski marka adının yalnızca NOTICE/README/telif izin listesinde kaldığını doğrula.
7. Kısa bakım penceresinde eski web/daemon'u durdurup aynı origin portunda yeni kümeyi aç.
8. Cloudflare üzerinden ana adres, agent/müşteri login ve `/careoncloud` yolunu doğrula.
9. Sorunda eski image, DB ve volume ile geri dön; kabul süresi dolmadan eski veriyi silme.

## 10. Açık riskler ve üretim öncesi zorunluluklar

### P0 — canlı kesim öncesi

- Aday konteynerin yeni DB/volume ile mavi/yeşil kabulü.
- Paket install/upgrade durumunun doğrulanması.
- Kanonik URL, cookie, header, log ve çalışma yollarında marka kalıntısı testi.
- En azından kritik tenant, katalog, request ve rapor regresyonu.
- Secret'ların repo ve SysConfig dışında güvenli saklanması.
- Belgelenmiş, denenmiş rollback.

### P0 — ticari pilot öncesi

- Tam tenant veri sızıntısı ve yetki testi.
- Generic Interface `TicketCreate` candidate MariaDB kabulü; GenericAgent/diger scheduler-daemon, non-MIME article backend, harici eklenti/doğrudan DB ve cross-system side effect yollarında atomik audit/outbox kapsamı.
- Gerçek dış OIDC sağlayıcısıyla uçtan uca SSO, logout/session politikası ve MFA beklentisi.
- Yedek/restore ve upgrade provası; RPO/RTO ölçümü.
- Cloudflare Access/WAF, origin sertleştirme ve bağımsız sızma testi.
- Bağımlılık/lisans taraması, SBOM, imzalı ve yeniden üretilebilir release artifact.
- Türkçe ve İngilizce ekranların uçtan uca dil/encoding incelemesi; bazı mevcut Markdown dosyalarında mojibake görülmektedir.
- Erişilebilirlik, performans/yük ve uzun süreli daemon testi.

### P1 — ürün olgunluğu

- Birleşik portal ve agent UX tasarımı.
- Major incident, problem, change/CAB ve knowledge akışlarının olgunlaştırılması.
- CMDB servis haritası, varlık/kontrat/entitlement bağlamı.
- OpenTelemetry, dashboard ve alarm teslim kanalları.
- Kurulum/upgrade sihirbazı ve müşteri yöneticisi dokümantasyonu.

### P2 — akıllı ESM

- Sağlayıcıdan bağımsız AI gateway.
- PII maskeleme, model/prompt sürümleme, kaynak bağlantısı, güven skoru ve maliyet limiti.
- İnsan onaylı sınıflandırma, özet, benzer olay, bilgi önerisi ve SLA risk tahmini.
- Müşteri verisinin varsayılan olarak model eğitiminde kullanılmaması.

## 11. Depo ve çalışma durumu

- Çalışma dizini: `CareOnCloud ESM` deposu.
- Geliştirme dalı: `codex/esm-foundation`.
- Çalışma ağacı son devir kontrolünde temizdir; güncel dal `codex/esm-foundation`, son commit `bc157ccde4` (`docs(esm): record static P0 gate rerun`). Kullanıcı değişikliklerini silen toplu reset/checkout yine yapılmamalıdır.
- Marka geçişi; silinen eski adlı dosyalar ve eklenen yeni adlı dosyalar nedeniyle özellikle geniş diff üretmektedir.
- Release arşivleri ve problem paketi kaynak arşivleri çalışma ağacında izlenmeyen dosyalardır; hangilerinin sürüm kontrolüne gireceği ayrıca belirlenmelidir.
- Git history tek başına mevcut prototip durumunu açıklamayabilir; bu belge ve `docs/esm/` altındaki tasarım belgeleri birlikte okunmalıdır.

Başlıca referanslar:

- `docs/esm/PRODUCT.md` — ürün konumlandırması.
- `docs/esm/ARCHITECTURE.md` — hedef mimari.
- `docs/esm/ROADMAP.md` — fazlar ve backlog.
- `docs/esm/STATUS.md` — ayrıntılı tarihsel test/özellik kaydı.
- `docs/esm/GPL-COMMERCIAL.md` — GPL ticari yaklaşımı.
- `docs/esm/branding/BRAND-01.md` — marka ve altyapı geçişi.
- `docs/esm/demo/SHOWCASE.md` — sentetik demo yaklaşımı.
- `development/careoncloud/README.md` — geliştirme runtime ve operasyon notları.

## 12. Değerlendiren yapay zekâ için önerilen sorular

Değerlendirme “kaç dosya yazıldı?” yerine aşağıdaki kanıt sorularına göre yapılmalıdır:

1. Her tenant-kapsamlı okuma ve yazma gerçekten merkezi policy katmanından mı geçiyor?
2. UI, REST, daemon, arama, cache ve export yolları aynı güvenlik modeline tabi mi?
3. Audit ile iş mutasyonu aynı transaction/outbox garantisini her domain için sağlıyor mu?
4. Katalog → servis uzantısı → talep tipi hiyerarşisi hem UI hem sunucu tarafında korunuyor mu?
5. Rapor query builder'ı yalnızca allow-list boyut/metrik kullanıyor mu ve cross-tenant veri üretebilir mi?
6. Yeni CareOnCloud imajı temiz kurulum ve mevcut veri upgrade senaryosunda tekrarlanabilir mi?
7. Eski marka yalnızca yasal köken/NOTICE alanlarında mı kalıyor?
8. GPL-3.0 dağıtımında karşılık gelen eksiksiz kaynak, build betikleri, üçüncü taraf lisansları ve SBOM veriliyor mu?
9. Türkçe/İngilizce deneyim yalnızca birkaç modülde değil tüm kritik akışlarda tamam mı?
10. Mevcut testler güncel çalışma ağacı üzerinde bağımsız ortamda yeniden üretilebiliyor mu?
11. Üretim iddiası için backup/restore, HA/DR, yük, güvenlik ve upgrade kanıtları mevcut mu?
12. AI özellikleri eklenirse PII, insan onayı, prompt/model sürümü ve audit zorunlulukları uygulanmış mı?

## 13. Net sonuç

CareOnCloud ESM, yalnızca görsel olarak yeniden adlandırılmış bir ticket sistemi değildir; servis kataloğu, tenant güvenliği, talep orkestrasyonu, SLA, audit, API, SCIM/OIDC ve raporlamaya yönelik ciddi bir modüler ürün temeli vardır. En güçlü tarafı, MSP/multi-tenant sınırını ve denetlenebilirliği ürünün merkezine koymasıdır.

Buna karşılık şu anda doğru tanım **“geniş kapsamlı ve test kanıtları bulunan geliştirme prototipi”**dir. Ticari ve üretim-hazır ürün sayılması için yeni CareOnCloud çalışma kümesine canlı geçişin tamamlanması, güncel tam regresyon, güvenlik/tenant izolasyonu, audit kapsamı, kimlik entegrasyonu, operasyonel dayanıklılık ve GPL release sürecinin bağımsız olarak doğrulanması gerekir.
