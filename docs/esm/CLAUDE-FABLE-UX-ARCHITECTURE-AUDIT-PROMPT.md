# Claude Fable için CareOnCloud ESM UX/UI ve Ürün Mimarisi İnceleme Talimatı

Bu dosyanın altındaki **"Fable'a verilecek ana talimat"** bölümü Claude Fable'a tek parça hâlinde verilmelidir. İnceleme sırasında mümkünse aşağıdaki kaynaklar da aynı çalışma alanına eklenmelidir:

1. `docs/esm/CAREONCLOUD-ESM-AI-MASTER-CONTEXT.md` — kanonik ürün ve teknik talimat
2. `docs/esm/STATUS.md` — doğrulanmış güncel durum ve açık riskler
3. `docs/esm/NOTES-FOR-CODEX.md` — devir ve release kanıtları
4. Güncel kaynak kod veya GitHub deposu: `akinarcak/careoncloud`, dal `codex/esm-foundation`
5. Canlı ve aday ortamların giriş, müşteri portalı, agent dashboard, talep, ticket, katalog, raporlama, CMDB, change ve admin ekran görüntüleri
6. Kullanıcının paylaştığı güncel canlı agent dashboard ekran görüntüsü

Fable kaynak kodu veya çalışan ürünü açamıyorsa bunu açıkça belirtmeli; görmediği ekranları görülmüş gibi raporlamamalıdır.

---

## Fable'a verilecek ana talimat

Sen CareOnCloud ESM için kıdemli ürün tasarımcısı, kurumsal UX mimarı, servis tasarımcısı ve frontend dönüşüm danışmanı olarak çalışacaksın. Görevin tek bir ekranı güzelleştirmek veya yüzeysel bir görsel konsept üretmek değildir. Mevcut ürünün **bütün kullanıcı deneyimini, bilgi mimarisini, ekran yapısını, terminolojisini, rol modelini ve teknik UI mirasını** inceleyip uygulanabilir bir iyileştirme ve geliştirme programına dönüştürmektir.

### 1. Önce bağlamı doğru kur

İlk ve kanonik kaynak `docs/esm/CAREONCLOUD-ESM-AI-MASTER-CONTEXT.md` dosyasıdır. Tamamını oku. Ardından `STATUS.md`, `NOTES-FOR-CODEX.md`, kaynak kod, template/skin yapısı, frontend kayıtları, paket ekranları ve sağlanan ekran görüntülerini incele.

Belge iddialarını gözlemlenmiş gerçek gibi kabul etme. Her önemli bulguyu şu kanıt düzeylerinden biriyle etiketle:

- `OBSERVED_IN_RUNNING_UI`
- `VERIFIED_IN_SOURCE`
- `SUPPORTED_BY_SCREENSHOT`
- `DOCUMENT_CLAIM_ONLY`
- `NOT_OBSERVED / NEEDS_ACCESS`

Kanıt bulunmayan noktaları varsayım olarak açıkça işaretle. Yalnızca ekran görüntüsüne bakarak tüm ürün hakkında kesin hüküm verme; ancak görüntüdeki somut sorunları da yumuşatma.

### 2. Ürünün değiştirilemez bağlamı

CareOnCloud ESM, OTOBO `rel-11_1` tabanından başlayan GPL-3.0 bir fork'tur. OTOBO'nun kökeni kaynak, lisans, NOTICE ve Git geçmişinde korunacaktır; fakat son kullanıcı deneyiminde OTOBO markası, `/otobo/` yolu, OTOBO terminolojisi, görselleri ve yardım bağlantıları görünmemelidir.

Kanonik son kullanıcı yolu `/careoncloud/`, statik içerik yolu `/careoncloud-web/` olmalıdır. Ürün Türkçe ve İngilizce eksiksiz çalışmalıdır; aynı ekran içinde iki dilin karışması kabul edilmez. Kullanıcı dili değiştirilebilir ve tercih kalıcı olmalıdır. Son kullanıcıya gösterilen bütün metinler yerelleştirilebilir olmalıdır.

CareOnCloud ESM'nin amacı yalnızca ticket yönetmek değildir. Ürün; IT, insan kaynakları, tesis, perakende operasyonu, saha hizmetleri, müşteri hizmetleri, tedarikçi ve sözleşme süreçlerini hizmet kataloğu ve sorumluluk modeli altında yöneten bir ESM platformudur.

İlk hedef pazar 100–2.000 kullanıcı ölçeğindeki kurumlar, Türkçe hizmet masaları ve MSP'lerdir. İlk sürüm için “ServiceNow'un tam alternatifi” veya “kurumsal BI platformu” gibi kanıtlanmamış iddialar kullanma.

CareOnCloud ESM geçiş çekirdeğidir; nihai ürün arayüzü değildir. Önerilerin mevcut işleyen backend kabiliyetlerini korumalı ve yeni kullanıcı arayüzünü CareOnCloud domain/API sınırları üzerinden aşamalı olarak ayırmalıdır. Büyük çaplı bir “her şeyi yeniden yaz” önerisi verme.

### 3. İncelenecek kullanıcı rolleri

Her rolü ayrı ihtiyaç, görev, bilgi yoğunluğu ve yetki bağlamıyla değerlendir:

1. **Hizmet alan / müşteri:** Hizmet bulur, katalogdan talep açar, durum/SLA/iletişim geçmişini izler, ek bilgi verir ve hizmet sonucunu değerlendirir.
2. **Agent / uzman:** Kuyruk, öncelik, görev, SLA, müşteri/tenant, hizmet, CI/varlık, bilgi ve iletişim bağlamında günlük iş yürütür.
3. **Hizmet sahibi:** Hizmet sağlığı, talep hacmi, SLA/OLA, kapasite, maliyet, kalite ve iyileştirme göstergelerini yönetir.
4. **Platform yöneticisi:** Tenant, kimlik, rol/yetki, entegrasyon, katalog, otomasyon, bildirim ve platform ayarlarını yönetir.
5. **MSP yöneticisi:** Birden fazla müşteri/tenant arasında güvenli sınırlar, sözleşmeler, entitlement, hizmet kalitesi ve operasyon görünürlüğünü yönetir.
6. **Denetçi:** Değiştirilemezlik iddiası taşımayan fakat zincir bütünlüğü bulunan audit kayıtlarını, filtreleri ve kanıt dışa aktarımını inceler.

Rol bazlı ana sayfa, navigasyon, varsayılan görünüm ve izin davranışı öner. Bütün rolleri aynı eski agent paneline sıkıştırma.

### 4. İnceleme kapsamı

#### 4.1 Çalışan ürün ve ekran envanteri

Erişilebilen bütün giriş noktalarını ve ekranları çıkar. En az şu alanları ara:

- Giriş, oturum, parola ve kimlik sağlayıcı akışları
- Müşteri portalı ana sayfası
- Hizmet kataloğu, kategori, hizmet, offering ve katalog öğesi
- Talep oluşturma, dinamik form, onay, fulfillment ve talep detayı
- Agent ana sayfası ve rol bazlı dashboard
- Ticket/kayıt listesi, kuyruklar, arama, oluşturma ve detay
- SLA/OLA, yaklaşan ihlal ve commitment görünümü
- Operations Center ve raporlama
- Service Portfolio / hizmet portföyü
- CMDB/PANO/varlık ve ilişki görünümü
- Change Enablement ve Problem
- Bilgi, arama ve yardım
- Bildirimler, görevler ve yaklaşan etkinlikler
- Kullanıcı tercihleri, dil, saat dilimi ve profil
- Tenant/MSP yönetimi
- Kimlik, OIDC ve SCIM yönetimi
- Webhook/API/entegrasyon yönetimi
- Audit ve kanıt dışa aktarımı
- Platform admin ve paket/yapılandırma ekranları
- Hata, boş durum, yüklenme, erişim reddi ve oturum sonu ekranları
- Mobil ve dar ekran davranışları

Her ekran için şu alanları içeren bir envanter oluştur:

| Alan | Açıklama |
|---|---|
| Ekran / rota | Görülen ad ve teknik rota |
| Birincil rol | Ekranı kullanan ana rol |
| Kullanıcı amacı | Kullanıcının tamamlamaya çalıştığı iş |
| Mevcut UI teknolojisi | Template, skin, JavaScript veya yeni frontend katmanı |
| Dil durumu | TR, EN, karışık veya çevrilemez sabit metin |
| Marka durumu | CareOnCloud, CareOnCloud ESM, D724 veya karışık |
| UX durumu | Çalışır, sürtünmeli, kritik kusurlu, eksik |
| Kanıt | Rota, ekran görüntüsü veya kaynak dosya |
| Yeniden kullanım kararı | Koru, iyileştir, sar/adapter kullan, değiştir |

#### 4.2 Bilgi mimarisi ve navigasyon

Mevcut üst menü, yan menü, modül adları ve sayfa hiyerarşisini incele. “Agent Assistant”, “Operations Center”, “Service Portfolio”, “Change Enablement”, “D724 Requests”, “PANO”, “Müşteriler”, “TAKVİM”, “BİLETLER” gibi karışık adların kullanıcı zihinsel modeliyle uyumunu değerlendir.

Şunları üret:

- Türkçe ve İngilizce kanonik menü adları
- Rol bazlı global navigasyon
- İkincil navigasyon ve breadcrumb modeli
- Global arama, hızlı oluşturma, bildirimler, yardım ve profil yerleşimi
- Tenant/organizasyon bağlamı seçiminin güvenli ve anlaşılır gösterimi
- Mobil/dar ekran navigasyon davranışı
- Eski teknik modül adlarının kullanıcıya görünen ürün dilinden kaldırılma planı

“Bilet” ve “ticket” terimlerini bağlama göre sorgula. CareOnCloud için “Talep”, “Kayıt”, “Olay”, “Görev” ve “Değişiklik” kavramlarının ne zaman kullanılacağını öner; teknik mirası son kullanıcı terminolojisine zorla taşımamaya dikkat et.

#### 4.3 Kritik kullanıcı yolculukları

En az aşağıdaki uçtan uca yolculukları adım adım incele ve yeniden tasarla:

1. Müşteri hizmet bulur ve katalogdan talep açar.
2. Müşteri açık talebinin durumunu, sorumlusunu ve hedef süresini izler.
3. Agent yeni ve SLA riski taşıyan işleri önceliklendirir.
4. Agent bir kaydı açar, bağlamı anlar, iletişim kurar, görev/CI/bilgi bağlar ve çözer.
5. Onaylayıcı talebi yeterli bağlamla onaylar veya reddeder.
6. Hizmet sahibi hizmet sağlığı ve SLA performansını inceler.
7. Platform yöneticisi katalog öğesi, form, rol ve entegrasyon yapılandırır.
8. MSP yöneticisi tenant değiştirir ve veri sınırını kaybetmeden müşteri performansını inceler.
9. Denetçi olay zincirini filtreler ve kanıt paketi dışa aktarır.
10. Kullanıcı dili ve saat dilimini seçer; seçim sonraki oturumlarda korunur.

Her yolculuk için:

- Mevcut durum sürtünmeleri
- Riskli veya belirsiz noktalar
- Hedef akış
- Gerekli ekranlar ve bileşenler
- Rol/yetki ve tenant etkisi
- TR/EN içerik ihtiyacı
- Boş, hata, bekleme ve başarı durumları
- Ölçülebilir kabul kriterleri
- Ölçülebilir ürün metriği

ver.

#### 4.4 Görsel sistem ve etkileşim tasarımı

Mevcut arayüzü yalnız renk ve logo açısından değerlendirme. Hiyerarşi, yoğunluk, taranabilirlik, görev önceliği, tablo ergonomisi, form yapısı, erişilebilirlik, geri bildirim ve veri görselleştirme açısından incele.

CareOnCloud için uygulanabilir bir tasarım sistemi başlangıcı oluştur:

- Marka kullanım ilkeleri ve logo güvenli alanı
- Renk token'ları ve semantik durum renkleri
- Tipografi ölçeği
- 4/8 tabanlı spacing sistemi
- Grid ve responsive breakpoint yaklaşımı
- Yüzey, border, elevation ve radius token'ları
- Buton, link, input, select, autocomplete ve tarih/saat bileşenleri
- Form bölümleri, doğrulama ve hata mesajları
- Tablo, filtre, sıralama, toplu işlem ve kaydedilmiş görünüm
- Badge, status, priority, SLA ve tenant göstergeleri
- Card, metric, timeline, activity stream ve relation panel
- Modal/drawer/toast kullanım kuralları
- Skeleton, empty state, error state ve permission state
- Grafiklerin sıfır veri ve düşük veri davranışı
- Klavye kullanımı, focus, contrast ve screen-reader ilkeleri
- Yoğun agent ekranı ile sade müşteri portalı arasındaki ortak ve ayrışan bileşenler

Hedef erişilebilirlik seviyesi **WCAG 2.2 AA** olmalıdır. Yalnız renk ile bilgi aktarma, küçük tıklama hedefleri, düşük kontrast, görünmeyen focus, anlamsız ikonlar ve klavye tuzaklarını özel olarak ara.

#### 4.5 Dil, içerik ve mikro metin

Türkçe ve İngilizceyi aynı önemde ele al. Aşağıdakileri incele:

- Aynı ekranda karışık dil
- Çevrilmemiş teknik terimler
- Kod içine gömülü metinler
- Büyük/küçük harf ve çoğul kullanımı
- Tarih, saat, sayı ve saat dilimi biçimleri
- Başarı, hata, onay ve geri dönüş mesajları
- Alan etiketi, yardım metni ve placeholder ayrımı
- SLA ve durum ifadelerinin anlaşılabilirliği
- Ürün, özellik ve navigasyon adlarının tutarlılığı

Örnek bir TR/EN kanonik terim sözlüğü çıkar. “Agent Assistant” için Türkçe kanonik ad **Destek Asistanı** olarak kabul edilecektir. Gerekirse İngilizce adı da daha açık bir ürün dili açısından sorgula.

#### 4.6 Mevcut teknik yapıyla uygulanabilirlik

Kaynakta görülen CareOnCloud ESM Template Toolkit şablonları, Agent/Customer skin CSS yapısı, frontend modül kayıtları, D724 paket ekranları ve mevcut JavaScript bağımlılıklarını incele. Şu üç yaklaşımı karşılaştır:

1. Eski şablon ve skin'leri kontrollü biçimde modernize etmek
2. Yeni CareOnCloud uygulama kabuğunu mevcut backend/API üzerine kademeli eklemek
3. Belirli ekranları strangler yaklaşımıyla yeni frontend'e taşımak

Her yaklaşım için değer, risk, maliyet, erişilebilirlik, test edilebilirlik, CareOnCloud ESM bağımlılığı ve geri dönüş kolaylığını değerlendir. Nihai öneriyi gerekçelendir.

Master Context'teki ayrışma sırasını dikkate al:

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
11. CareOnCloud ESM DB/runtime bağımlılığının kaldırılması

Ticket ve e-posta çekirdeğini erken yeniden yazmayı önerme. Yeni ekranların doğrudan CareOnCloud ESM tablosuna bağlanmasını da önerme; CareOnCloud domain/API veya açıkça tanımlanmış adapter sınırı kullan.

### 5. Mevcut canlı ekranla ilgili doğrulanması gereken başlangıç bulguları

Kullanıcının paylaştığı agent dashboard ekran görüntüsünde aşağıdaki sorunlar görülmektedir. Bunları başlangıç hipotezi olarak doğrula, genişlet veya yanlışla:

- Adres satırında kullanıcıya görünen `/careoncloud/index.pl` yolu
- Aynı menüde Türkçe ve İngilizce modül adları
- “Welcome to CareOnCloud ESM!” gibi eski ürün verisi/metni
- Kullanıcıya gösterilen İngilizce saat dilimi uyarısı
- Eski ve yoğun yatay navigasyon
- Birincil kullanıcı görevini öne çıkarmayan dashboard
- Boş tabloların ve sıfır değerli grafiğin geniş alan kaplaması
- Küçük yazı, zayıf görsel hiyerarşi ve eski tablo sunumu
- Türkçe başlıklarla İngilizce kolon/yan panel adlarının karışması
- Teknik/kod adı niteliğindeki `D724` ve belirsiz `PANO` adlarının görünmesi
- Eski test kayıtlarının ürün deneyiminde görünmesi
- Rol bazlı odak ve eylem önceliğinin anlaşılmaması

Bu liste nihai denetim değildir; yalnızca başlangıç kanıtıdır.

### 6. Zorunlu çıktı biçimi

Çıktını aşağıdaki sırada üret. Genel tasarım tavsiyeleriyle yetinme.

#### A. Yönetici özeti

- Ürünün bugünkü UX olgunluk seviyesi
- En kritik beş sorun
- En büyük beş fırsat
- Ticari pilotu engelleyen UX kapıları
- 90 günlük gerçekçi hedef durum

#### B. Kanıt ve kapsam kaydı

- İncelenen dosyalar, rotalar, ekranlar ve ekran görüntüleri
- Erişilemeyen alanlar
- Kanıt etiketleri
- Varsayımlar ve doğrulama ihtiyaçları

#### C. UX skor kartı

Aşağıdaki alanları 0–5 arasında puanla ve her puanı kanıtla:

- Marka bütünlüğü
- Bilgi mimarisi
- Navigasyon
- Görev tamamlama
- Rol bazlı deneyim
- TR/EN bütünlüğü
- İçerik/mikro metin
- Görsel hiyerarşi
- Form kullanılabilirliği
- Veri yoğun ekran ergonomisi
- Responsive kullanım
- WCAG 2.2 AA uyumu
- Hata/boş/yükleme durumları
- Tenant/MSP bağlam görünürlüğü
- Güven ve kurumsal ürün algısı

#### D. As-is ekran ve yolculuk haritası

Ekran envanteri, rol eşlemesi, mevcut navigasyon ağacı ve kritik yolculuk haritalarını ver. Yinelenen, çakışan, belirsiz veya teknik kökenli menüleri işaretle.

#### E. Bulgular backlog'u

Her bulguyu aşağıdaki kolonlarla tablo hâline getir:

| ID | Kanıt | Rol | Ekran/yolculuk | Sorun | Kullanıcı/iş etkisi | Önem | Kök neden | Öneri | Bağımlılık | Kabul kriteri |
|---|---|---|---|---|---|---|---|---|---|---|

Önem sınıfları:

- `P0`: Güven, erişim, tenant bağlamı, kritik görev, marka ihlali, iki dil veya pilot kabulünü engeller
- `P1`: Temel iş akışını ciddi ölçüde yavaşlatır veya hata ihtimalini artırır
- `P2`: Verimlilik, tutarlılık ve öğrenilebilirlik iyileştirmesi
- `P3`: İleri seviye farklılaşma veya optimizasyon

#### F. Hedef bilgi mimarisi

Müşteri, agent, hizmet sahibi, admin, MSP yöneticisi ve denetçi için hedef menü ağaçlarını ayrı ayrı ver. Türkçe ve İngilizce adları yan yana göster. Global ve role özgü alanları ayır.

#### G. Hedef ekran tasarımları

En az aşağıdaki ekranlar için düşük/orta ayrıntılı wireframe veya açıklamalı düzen üret:

1. Müşteri portalı ana sayfası
2. Hizmet kataloğu ve katalog öğesi
3. Talep oluşturma adımları
4. Müşteri talep detay/timeline ekranı
5. Agent rol bazlı ana sayfası
6. Agent iş listesi/kuyruk ekranı
7. Agent ticket/request çalışma alanı
8. Operations Center / hizmet sağlığı
9. Hizmet sahibi dashboard'u
10. Tenant/MSP yönetim görünümü
11. Audit inceleme ve dışa aktarım ekranı
12. Platform admin ana sayfası

Wireframe'lerde gerçekçi Türkçe örnek içerik kullan; lorem ipsum kullanma. Aynı ana ekranların İngilizce karşılığında uzunluk değişimini de kontrol et. Her ekranda birincil görev, birincil CTA, kritik durum, boş durum ve hata durumunu belirt.

#### H. Tasarım sistemi başlangıç paketi

Token'ları, temel bileşenleri, varyantları, erişilebilirlik kurallarını ve hangi ekranlarda kullanılacaklarını belirt. Tasarım sisteminin eski CareOnCloud ESM skin'ine nasıl köprülenip zamanla bağımsızlaştırılacağını açıkla.

#### I. Aşamalı geliştirme yol haritası

Planı yalnız tema isimleriyle değil, geliştirilebilir dilimlerle oluştur:

- `P0 / Pilot kapıları`
- `P1 / Yeni müşteri portalı`
- `P1 / Yeni agent çalışma kabuğu`
- `P2 / Admin ve MSP deneyimi`
- `P2 / Tasarım sistemi yaygınlaştırma`
- `P3 / CareOnCloud ESM UI bağımsızlığı`

Her dilim için:

- Kullanıcı sonucu
- Dahil olan ekranlar
- Tasarım işi
- Frontend işi
- API/domain ihtiyacı
- Veri/permission bağımlılığı
- Test yaklaşımı
- Telemetri/başarı metriği
- Geri dönüş planı
- Yaklaşık efor: `S`, `M`, `L`, `XL`
- Ardışıklık ve bloklayan bağımlılıklar

ver.

Ayrıca işleri iki uygulama sınıfına ayır:

- **Düşük muhakeme / düşük token ile uygulanabilir:** metin kataloğu, token tanımları, basit bileşen varyantları, route/brand tarama testleri, screenshot regression, erişilebilirlik otomasyonu gibi açık kabul ölçütlü işler.
- **Yüksek muhakeme / kıdemli model veya insan kararı gerekli:** bilgi mimarisi, persona çatışmaları, agent yoğunluk dengesi, tenant bağlamı, tasarım sistemi mimarisi, API sınırı ve kritik yolculuk yeniden tasarımı.

#### J. İlk uygulanacak backlog

İlk iki sprint için küçük, atomik ve test edilebilir iş kartları üret. Her kartta şunlar bulunsun:

- Başlık
- Kullanıcı hikâyesi
- Kapsam
- Kapsam dışı
- Tasarım kabul kriterleri
- Teknik kabul kriterleri
- TR/EN kabul kriterleri
- WCAG kabul kriterleri
- Test/kanıt yöntemi
- Bağımlılıklar
- Geri dönüş yolu

İlk sprint yalnız kozmetik makyaj olmasın. Kullanıcıya görünen `/careoncloud/`, CareOnCloud ESM/D724 kalıntıları, karışık dil, saat dilimi uyarısı, eski fixture/veri, navigasyon tutarsızlığı ve kritik rol ana sayfaları P0 değerlendirmesine alınmalıdır.

#### K. Karar günlüğü

Ürün sahibinin karar vermesi gereken noktaları ayrı bir tabloda ver. Her karar için seçenekleri, önerini, gerekçeyi, maliyeti ve geri dönüş etkisini yaz. Kanıtla çözülebilecek bir konuyu gereksiz yere ürün kararı olarak bırakma.

### 7. Kalite eşiği

Çıktı şu koşulları sağlamıyorsa tamamlanmış sayma:

- Yalnızca tek ekran veya yalnız görsel stil incelenmişse
- Müşteri, agent ve admin deneyimleri ayrılmamışsa
- Türkçe/İngilizce bütünlüğü somut kabul kriterlerine bağlanmamışsa
- `/careoncloud/` ve CareOnCloud ESM marka kalıntıları ele alınmamışsa
- Tenant/MSP bağlamı ve yetki görünürlüğü değerlendirilmemişse
- WCAG 2.2 AA, klavye ve responsive kullanım incelenmemişse
- Öneriler mevcut kaynak/teknik yapı ile ilişkilendirilmemişse
- Bulgular P0–P3 sırasına ve atomik iş kartlarına dönüştürülmemişse
- Tasarım ile frontend/API/domain bağımlılıkları ayrıştırılmamışsa
- Görülmeyen alanlar görülmüş gibi raporlanmışsa

Sonuçta hedef; eski CareOnCloud ESM agent panelinin renklerini değiştirmek değil, çalışan CareOnCloud kabiliyetlerini koruyarak **güvenilir, iki dilli, rol bazlı, erişilebilir ve aşamalı olarak bağımsızlaşabilen bir kurumsal hizmet deneyimi** tanımlamaktır.

