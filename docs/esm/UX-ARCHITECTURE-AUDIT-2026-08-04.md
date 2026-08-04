# CareOnCloud ESM — UX / Bilgi Mimarisi / Ürün Deneyimi Denetimi

**Tarih:** 4 Ağustos 2026
**Dal:** `codex/esm-foundation` · **HEAD:** `3018cb3cf`
**Denetimi yapan:** Claude Opus 5 (Claude Code oturumu)
**Talimat kaynağı:** `docs/esm/CLAUDE-FABLE-UX-ARCHITECTURE-AUDIT-PROMPT.md`
**Kanonik bağlam:** `docs/esm/CAREONCLOUD-ESM-AI-MASTER-CONTEXT.md` (tamamı okundu), `docs/esm/STATUS.md`

---

# A. Yönetici özeti

## A.0 En önemli tek bulgu — kanıt yorumunu değiştirir

**Canlı ortam (`https://esm.arcak.net`) güncel kaynak kodun karşılığı değildir. Rebrand öncesi eski bir dağıtımdır.**

| Kontrol | Canlı sonuç | Kaynak koddaki durum |
|---|---|---|
| `/careoncloud/index.pl` | **404** | `Kernel/Config/Defaults.pm:112` → `ScriptAlias = 'careoncloud/'` |
| `/careoncloud/index.pl` | **200** | kaynakta artık kanonik değil |
| `/careoncloud-web/...` | **404** | `Defaults.pm:360` → `Frontend::WebPath = '/careoncloud-web/'` |
| `/otobo-web/...` | **200**, tüm CSS/JS/ikon buradan | — |
| Karşılama kaydı | `Welcome to CareOnCloud ESM!` (kullanıcı ekran görüntüsü) | `scripts/database/careoncloud-initial_insert.xml:1283` → `Welcome to CareOnCloud ESM!` |
| Müşteri logo dosyası | `careon-signet.png` | repoda `careoncloud-signet.png` **ve** template `careon-signet.png` istiyor → isim tutarsızlığı |

Bunun iki sonucu var:

1. Talimatın §5'indeki başlangıç hipotezlerinin bir kısmı **dağıtım gecikmesidir**, kaynak kod kusuru değildir (`/careoncloud/` yolu, `Welcome to CareOnCloud ESM!` verisi). Bunlar cutover ile çözülür; yeniden tasarım gerektirmez.
2. Bir kısmı ise **güncel kaynakta hâlâ duruyor** ve cutover bunları çözmez. En ağırı `Kernel/Output/HTML/Layout.pm:4221`.

Bu ayrımı yapmadan verilen her UX yol haritası yanlış işi önceliklendirir.

## A.1 Ürünün bugünkü UX olgunluk seviyesi

**Seviye 1.5 / 5 — "Çalışan backend, henüz ürünleşmemiş arayüz."**

CareOnCloud'un ayırt edici değeri (katalog, request state machine, commitment/SLA, tenant guard, audit, reporting, API) gerçek koda sahiptir. Ancak bu kabiliyetlerin **kullanıcıya görünen yüzü yoktur veya iskelet düzeydedir**. Somut ölçüt: 18 D724 paketinde toplam **13 frontend modülü ve 10 şablon** vardır; paketlerin hiçbirinde **tek satır CSS veya JS yoktur** (`find packages -name "*.css" -o -name "*.js"` → boş). Yani bütün D724 ekranları CareOnCloud ESM Agent skin'inin varsayılan stiline binmektedir ve kendi görsel dilleri yoktur.

Bu, "renkleri değiştirelim" sorunu değildir. Ürünün altı personasından **üçünün (platform yöneticisi, MSP yöneticisi, denetçi) hiç ekranı yoktur.**

## A.2 En kritik beş sorun

| # | Sorun | Kanıt |
|---|---|---|
| 1 | **Canlı ortamda ~40 gerçek Türk şirketinin adı demo tenant olarak duruyor** (Anadolu Hayat Emeklilik, İş Bankası Almanya, Milli Reasürans, QNB Finans, Mavi, Setur, BKM, Eczacıbaşı Bilişim…). Master Context §13.4 bunu açıkça yasaklıyor. **Güncel kaynakta bu adlar yoktur** — üç seed script'i de sentetik ad kullanıyor; bu eski DB verisidir ve veri temizliğiyle çözülür. | `OBSERVED_IN_RUNNING_UI` + kaynakta yokluğu doğrulandı |
| 2 | Müşterinin gördüğü **ilk ekranda** "Your Tickets. Your CareOnCloud ESM." yazıyor ve CareOnCloud ESM'nun varsayılan tavus kuşu görseli var. Kaynakta hardcoded fallback. | `OBSERVED_IN_RUNNING_UI` + `VERIFIED_IN_SOURCE` `Layout.pm:4221` |
| 3 | **Müşteri açtığı talebi takip edemez.** Müşteri portalında talep listesi/detay/timeline ekranı yok; `CustomerD724Request` yalnızca `Submit` alt-eylemine sahip. | `VERIFIED_IN_SOURCE` |
| 4 | **Tenant/MSP, kimlik, webhook ve audit için hiç arayüz yok.** Platform yöneticisi, MSP yöneticisi ve denetçi personaları ekransız. | `VERIFIED_IN_SOURCE` |
| 5 | **Türkçe ürün dili yok denecek kadar eksik** ve karışık. Aynı ekranda İngilizce widget başlıkları + Türkçe kolon adları + çevrilmemiş `TOTAL` bir arada. | `OBSERVED_IN_RUNNING_UI` — agent dashboard |
| 6 | **Marka sözleşme testi yalnızca dosya yolu tarıyor**, ekrana basılan metni taramıyor; bu yüzden 2. madde testlerden geçti. | `VERIFIED_IN_SOURCE` `Test-CareOnCloudBrand.ps1:38-53` |

## A.3 En büyük beş fırsat

1. **Hizmet kataloğu → talep → SLA zinciri uçtan uca çalışıyor.** Rakiplerde bu zinciri kurmak aylar sürer; burada backend hazır, eksik olan yalnızca kabuk. En hızlı görünür değer burada.
2. **Tenant bağlamı her ekranda zaten veri modelinde var.** MSP deneyimi sıfırdan kurulmayacak; yalnızca görünür ve güvenli hâle getirilecek.
3. **Türkçe, kopyalanamayan bir konumlandırma.** ServiceNow/Jira'nın Türkçesi mekaniktir. Doğru terminoloji sözlüğü tek başına satış argümanıdır.
4. **Şablonlar temiz ve küçük.** 10 şablonun tamamı birkaç yüz satır; tasarım sistemi uygulamak büyük bir refactor değil, dar bir iş.
5. **Audit zinciri var, arayüzü yok.** Denetçi ekranı düşük maliyetle eklenebilir ve regüle müşteride kapı açar.

## A.4 Ticari pilotu engelleyen UX kapıları

Bunlar geçilmeden pilot müşteriye ekran gösterilmemelidir:

- **G1** — Müşteri giriş ekranında CareOnCloud ESM markası ve sloganı (`P0-01`)
- **G2** — Kullanıcıya görünen `/careoncloud/` ve `/otobo-web/` yolları (`P0-02`)
- **G3** — Müşterinin talebini takip edememesi (`P0-05`)
- **G4** — Türkçe arayüzün eksik/karışık olması (`P0-07`, `P0-08`)
- **G5** — Tenant bağlamının agent ekranında ham `TenantID` olarak gösterilmesi ve kazara değiştirilebilmesi (`P0-06`)
- **G6** — `<html lang="">` boş; ekran okuyucu dili belirleyemiyor **ve** Türkçe büyük harf bozuluyor (`YENI`) — WCAG 2.2 **A** seviyesi ihlali (`P0-09`, `P0-13`)
- **G7** — Demo verisinde gerçek şirket adları (`P0-11`) — bu bir UX değil **hukuk/itibar** kapısıdır ve demo yapılmadan önce kapatılmalıdır
- **G8** — Agent talebi kimin açtığını göremiyor; talep sahibi hash olarak görünüyor (`P0-12`)

## A.5 90 günlük gerçekçi hedef durum

90 günde **yeni bir ürün arayüzü** hedeflenmemelidir. Gerçekçi hedef:

> Türkçe ve İngilizce eksiksiz çalışan, CareOnCloud ESM markası görünmeyen, `/careoncloud/` üzerinden sunulan; müşterinin katalogdan talep açıp **takip edebildiği**, agent'ın SLA riskli işi önce gördüğü, MSP yöneticisinin tenant'ı isimle ve güvenle değiştirebildiği, denetçinin audit kaydını filtreleyip dışa aktarabildiği bir pilot sürümü.

Bu, mevcut CareOnCloud ESM kabuğu **korunarak** ulaşılabilir. Yeni frontend kabuğu 90 gün içinde başlar ama bitmez.

---

# B. Kanıt ve kapsam kaydı

## B.1 Kanıt etiketleri

- `OBSERVED_IN_RUNNING_UI` — canlı `esm.arcak.net` üzerinde tarayıcıyla gözlendi (kimlik doğrulaması gerektirmeyen yüzey)
- `VERIFIED_IN_SOURCE` — `codex/esm-foundation` @ `3018cb3cf` üzerinde dosya/satır ile doğrulandı
- `SUPPORTED_BY_SCREENSHOT` — kullanıcının tarif ettiği agent dashboard görüntüsü (görsel bana **iletilmedi**; talimat metnindeki tarife dayanır)
- `DOCUMENT_CLAIM_ONLY` — yalnızca dokümanda iddia ediliyor
- `NOT_OBSERVED / NEEDS_ACCESS` — erişilemedi

## B.2 İncelenen kaynak dosyalar

```
docs/esm/CAREONCLOUD-ESM-AI-MASTER-CONTEXT.md      (1139 satır, tamamı)
docs/esm/STATUS.md                                  (açık riskler bölümü)
Kernel/Config/Defaults.pm                           (yol/marka ayarları)
Kernel/Output/HTML/Layout.pm                        (login render, 4205-4240)
Kernel/Output/HTML/Templates/Standard/CustomerLogin.tt
Kernel/Language/tr.pm                               (çekirdek TR sözlüğü)
Kernel/Config/Files/XML/Framework.xml               (nav + dashboard widget'ları)
Kernel/Config/Files/XML/Ticket.xml                  (agent nav)
scripts/database/careoncloud-initial_insert.xml     (seed veri)
development/d724/Test-CareOnCloudBrand.ps1          (marka sözleşme testi)
packages/D724*/Kernel/Config/Files/XML/*.xml        (17 dosya, frontend kaydı)
packages/D724*/Kernel/Output/HTML/Templates/...     (10 şablonun tamamı)
packages/D724*/Kernel/Language/tr_*.pm              (8 dosya)
packages/D724Request/Kernel/Modules/CustomerD724Request.pm
```

## B.3 Gözlenen canlı yüzeyler

| Rota | HTTP | Gözlem |
|---|---|---|
| `/careoncloud/index.pl` | 200 | Agent login. Başlık `Login - CareOnCloud ESM`. Careon logosu var. HTML içinde 24 adet `careoncloud` geçiyor. |
| `/careoncloud/customer.pl` | 200 | Müşteri login. `<h1>Your Tickets. Your CareOnCloud ESM.</h1>` + CareOnCloud ESM tavus kuşu arka planı. |
| `/careoncloud/public.pl` | 200 | Erişilebilir |
| `/careoncloud/index.pl` | **404** | Kanonik yol canlıda yok |
| `/careoncloud/customer.pl` | **404** | — |
| `/careoncloud-web/...` | **404** | — |

Mobil (375×812) login kontrolü: yatay taşma **yok**, birincil buton 279×48 px, kullanıcı adı alanı 58 px, `<label for>` **mevcut**. Bu üç nokta iyi durumda — abartmadan kaydedilmiştir.

## B.4 Kimlik doğrulamalı gözlem — `OBSERVED_IN_RUNNING_UI`

Kullanıcı `demo.agent` oturumunu **kendisi açtı** (parola girmek benim için kapalı bir işlemdir). Oturum açıldıktan sonra aşağıdaki agent ekranları doğrudan gözlendi:

| Ekran | Rota | Gözlem |
|---|---|---|
| Agent dashboard | `index.pl?` | 8 CareOnCloud ESM varsayılan widget'ı; 4 tanesi tamamen boş (`none`) |
| Operasyon Merkezi | `?Action=AgentD724Operations` | KPI'lar, 3 tablo, tenant seçici |
| Talepler | `?Action=AgentD724Request` | Tek talep, tenant seçici, SLA satırları |

### B.4.1 Agent dashboard — doğrulanan bulgular

- `<html lang>` **boş** (kimlik doğrulamalı sayfalarda da) — WCAG 3.1.1 (A)
- Sayfa HTML'inde **98 adet** `otobo` geçişi; `otobo.io/` ve `otobo.io/de/forums/otobo/otobo-forum` bağlantıları canlı
- Sarı banner: *"Please select a time zone in your preferences and confirm it by clicking the save button."* — **her sayfada**, İngilizce
- `2015071510123456 · Welcome to CareOnCloud ESM!` kaydı listede görünür (OTRS/CareOnCloud ESM 2015 örnek verisi)
- **Aynı ekranda üç dilli karışım:** İngilizce widget başlıkları (`Reminder Tickets`, `Escalated Tickets`, `New Tickets`, `Open Tickets`, `Ticket Queue Overview`, `none`) + Türkçe kolon adları (`Kuyruğa koy`, `yeni`, `açık`, `bekleyen hatırlatıcı`) + çevrilmemiş `Total`
- **`Kuyruğa koy`** — `Queue` (isim) fiil olarak yanlış çevrilmiş
- **`YENI` ↔ `YENİ` hatası:** kolon adları CSS `text-transform: uppercase` ile büyütülüyor. `<html lang>` boş olduğu için tarayıcı Türkçe büyük harf kuralını uygulamıyor ve `yeni` → **`YENI`** oluyor (`YENİ` olmalı). **Bu, P0-09'un doğrudan görsel sonucudur** — boş `lang` yalnızca ekran okuyucuyu değil, gözle görülen metni de bozuyor.
- Ekranın ilk yarısını dört boş tablo kaplıyor; eylem gerektiren içerik yok
- 961 px genişlikte CareOnCloud ESM **mobil moda** düşüyor: üst menü hamburger'a giriyor, altta manuel `Switch to desktop mode` bağlantısı çıkıyor. Yatay taşma yok, ancak agent iş istasyonu için bu kırılma noktası fazla agresif.
- Menü tamamen İngilizce ve **D724 modülleri en solda**: `Agent Assistant · Operations Center · Service Portfolio · Change Enablement · D724 Requests · Dashboard · Customers · Calendar · Tickets…` — çekirdek `Dashboard` beşinci sıraya itilmiş

### B.4.2 Operasyon Merkezi — doğrulanan bulgular

- **`D724KPIGrid` çalışma zamanında `display: block`, `grid-template-columns: none`** — kaynak tahmini birebir doğrulandı. Dört KPI alt alta, her biri tam genişlikte widget.
- **`D724KPI` yazı boyutu 16 px** — KPI rakamı gövde metniyle aynı boyutta. `10`, `24`, `3`, `87.5%` değerleri hiyerarşisiz.
- Ham makine değerleri ekranda: `awaiting_approval`, `fulfilled`, `in_fulfillment`, `ola`, `resolution`, `breached`, `met`, `paused`
- `87.5%` — İngiliz ondalık ayracı; TR'de `%87,5` olmalı
- Tenant seçicide **`onchange` yok** ve adlar görünüyor → bu ekran doğru davranıyor; sorun `AgentD724Request`'e özgü (C-14'teki tutarsızlık tespiti doğrulandı)
- **"Custom report designer" bölümü canlıda yok** — kaynakta var. A.0'daki "canlı ≠ kaynak" tespitinin ek kanıtı.

### B.4.3 Talepler ekranı — doğrulanan bulgular

- `<h1>D724 Requests</h1>` — kod adı kullanıcıya görünür
- `<select name="TenantID" onchange="this.form.submit()">` **çalışma zamanında doğrulandı** — WCAG 3.2.2 (A)
- Tenant seçenekleri **ham slug**: `d724-demo`, `demo-anadolu-hayat-emeklilik`, `demo-i-s-bankasi-almanya`, `demo-i-stanbul-modern-eczacibasi-bilisim` — Türkçe karakterler bozulmuş (`İş` → `i-s`, `İstanbul` → `i-stanbul`)
- **Talep sahibi 64 karakterlik hash olarak gösteriliyor:** `Requester: customer:925bd0322082b6bfa7b0ebf3228daa3d4ee47d3e58b492ca12836edf8473113e` — agent talebi kimin açtığını göremiyor
- Durumlar ham: `REQ-0000000203 — fulfilled`, `response / first-response: met`, `ola / internal-ola: met`
- Tarihler ISO: `2026-07-27 08:45:00` — TR'de `27.07.2026 08:45` olmalı
- Liste yok, filtre yok, sıralama yok, sayfalama yok; eylem yoksa açıklayıcı metin de yok

### B.4.4 Katalog yönetimi (`AdminD724Catalog`) — doğrulanan bulgular

Agent hesabı admin yetkisi taşıdığı için bu ekran da gözlendi.

- `<h1>D724 Service Catalog</h1>` — kod adı admin ekranında da görünür
- **Şablonda sıfır `<label>` var** (`AdminD724Catalog.tt`: 0 `<label>`, 9 `placeholder`). Gözlemde her `input`/`select` için `label` boş döndü. Ekran okuyucu kullanıcısı bu ekranı **kullanamaz** — WCAG 3.3.2 / 4.1.2 (A)
- **Ekranda hiç `<table>` yok.** "Liste" aslında üst üste dizilmiş satır-içi formlardan oluşuyor; her satırın kendi `Save` butonu var. Başlık satırı, sıralama, gruplama, toplu işlem yok.
- 51 offering'in tamamı tek sayfada, hizmete göre gruplanmadan listeleniyor
- Metin kutuları içeriği kesiyor: `Bulut ve Platform Yönetimi` sığmıyor, açıklamalar ~30 karakterde kırpılıyor
- Ham değerler ekranda: `draft`, `active`, `manual`, `process` (çevrilmemiş); servis anahtarları slug olarak (`atomic-audit-service`, `cloud-platform`, `cybersecurity`)
- **Test artefaktı ürün verisinde:** `Atomic Audit Service Update` / `Atomic Audit Service Updated` / `atomic-audit-offering`, `draft` durumunda. Atomiklik testinden kalmış kayıtlar demo kataloğunda duruyor.
- Türkçe hizmet adları ile İngilizce açıklamalar aynı listede (`Bulut servisleri, modern platf…` ↔ `Devices and workplace servi…`, `Catalog transaction acceptan…`)

### B.4.5 Taahhüt yönetimi (`AdminD724Commitment`) — doğrulanan bulgular

- **SLA/OLA politikası ham JSON olarak yazdırılıyor.** Yönetici, ürünün en önemli ticari özelliğini ~150 px yüksekliğinde bir `<textarea>` içine elle JSON yazarak tanımlıyor:
  `[{"key":"first-response","type":"response","target_seconds":3600,"warning_percent":75,"start_signal":"request_created","stop_signal":"first_response","escalation_actions":[]}]`
  Alan bazlı form, doğrulama geri bildirimi veya yardım metni yok.
- `AdminD724Commitment.tt`: **1 `<label>`** (yalnız Tenant seçicisi), 5 `placeholder`. Düzenleme satırındaki `CalendarID` ve `WarningPercent` alanlarının **ne `label`'ı ne `placeholder`'ı var** — ekranda yalnızca `0`, `14400`, `80` görünüyor. Bir yönetici bu sayıların ne anlama geldiğini ekrandan öğrenemez; **birim de yazmıyor** (saniye).
- `onchange="this.form.submit()"` **ikinci kez** burada; tenant seçeneği yine ham `Data.TenantID`
- `Status` seçeneği çevrilmemiş (`active` / `inactive` sabit metin)
- **Gerçek hata:** düzenleme satırındaki `Status` seçicisi mevcut değeri ilk seçenek olarak ekleyip ardından `active` ve `inactive`'i de listeliyor → mevcut durum `active` ise açılır listede `active, active, inactive` çıkıyor

### B.4.6 Tercihler ekranı (`AgentPreferences`) — doğrulanan bulgular

- **`translate.otobo.org` bağlantısı ve *"You can help translating OTOBO"* metni** dil ayarının hemen altında duruyor. Her kullanıcının uğradığı ekranda hem marka ihlali hem başka bir projeye yönlendirme. (`P0-16`)
- **Dil listesinde `Türkçe - Turkish (in process)`** yazıyor. Ana pazarı Türkiye olan bir üründe dil seçici Türkçeyi "devam ediyor" diye etiketliyor. Ayrıca **50 dil** listeleniyor; Master Context §3.1 yalnız TR/EN'i zorunlu tutuyor — kullanıcı Korece'ye geçerse yarım çevrilmiş bir ürün görüyor. (`P0-17`)
- **Varsayılan saat dilimi `UTC`.** `Europe/Istanbul` listede var ama seçili değil. `P0-14`'teki kalıcı sarı banner'ın kök nedeni budur: ürün Türkiye kurulumunda bile UTC ile başlıyor ve her kullanıcıyı elle düzeltmeye zorluyor. (`P0-18`)
- **Gravatar entegrasyonu** kullanıcının e-posta adresiyle dış servise kaydolmayı öneriyor — regüle müşteride veri çıkışı sorusu. (`P2-07`)
- Ekranın tamamı İngilizce (oturum EN olduğu için beklenen); parola değiştirme, avatar, dil, saat dilimi ve "Out Of Office Time" bölümleri var.

### B.4.7 Olumlu tespit — müşteri dil tercihi mevcut

`Framework.xml:4505` — `CustomerPreferencesGroups###Language`, `Active=1`, etiketi *"Interface language"*. Yani müşteri arayüz dilini tercihlerden **değiştirebiliyor** ve tercih `UserLanguage` olarak kalıcı. Eksik olan, giriş ekranında dil seçici bulunmaması ve `CustomerHeader.tt` / `CustomerNavigationBar.tt` içinde dil anahtarının olmaması.

## B.5 Hâlâ erişilmemiş alanlar — `NEEDS_ACCESS`

- **Müşteri portalı iç sayfaları** (katalog, talep formu, makbuz) — müşteri hesabı/parolası oluşturulmadığı için giriş yapılamadı. Bu ekranlar bu raporda **yalnızca kaynak koddan** değerlendirilmiştir (bkz. B.7).
- Kullanıcı tercihleri / dil / saat dilimi ekranı
- Ticket detay, arama, kuyruk ekranları
- Service Portfolio, Change, Assist ekranları
- Hata / yetki reddi / oturum sonu ekranları
- Paket yöneticisi ve çekirdek admin ekranları

## B.7 Müşteri portalı — kaynak kod incelemesi (`VERIFIED_IN_SOURCE`)

Müşteri hesabı olmadığı için portal çalışır hâlde görülmedi. `CustomerD724Catalog.pm`, `CustomerD724Request.pm` ve iki şablon satır satır okundu; aşağıdakiler koddan kesindir:

- **Katalog tek sayfada, sayfalama ve arama olmadan basılıyor.** `Run()` içindeki varsayılan dal bütün hizmetleri, her hizmetin bütün offering'lerini ve her offering'in bütün katalog öğelerini iç içe döngüyle render ediyor. 6 alan / 51 offering ölçeğinde bu çok uzun bir sayfa demektir; filtre veya arama kutusu yoktur.
- **Boş katalog için boş durum yok.** `$Result->{Data}` boşsa döngüler hiç çalışmaz ve kullanıcı yalnızca boş bir seçim formu görür.
- **Yetki reddi ile "bulunamadı" aynı yanıtı veriyor** (`CustomerNoPermission`). Güvenlik açısından doğru (varlık sızdırmıyor), fakat kullanıcı ne yapması gerektiğini öğrenemiyor.
- **Dinamik form alanları çevrilemiyor.** `_ItemRender` alanları `FormSchema->{Schema}->{fields}` üzerinden bloklara veriyor; şablon `[% Data.label | html %]` ile **`Translate()` olmadan** basıyor. Katalog içeriği tek dilde kalır (P1-02).
- **Talep gönderiminden sonra dönüş yok.** `CustomerD724Request.pm` yalnızca `Submit` alt-eylemine sahip; `Run()` içinde başka dal yok. Kullanıcı makbuz sayfasından sonra kataloğa dönmek dışında bir yol bulamaz (P0-05).
- **Durum ham basılıyor:** `CustomerD724Request.tt` içinde `[% Data.Request.Status | html %]` ve `[% Commitment.ObjectiveType %] / [% Commitment.ObjectiveKey %]` — müşteri `fulfilled`, `ola`, `internal-ola` gibi makine değerleri görür (P0-08).
- **Olumlu:** müşteri şablonlarında `<label for>` bağları **doğru** kurulmuş, `required` kullanılmış, `IdempotencyKey` ile çift gönderim engellenmiş. Müşteri tarafı, admin tarafından erişilebilirlik açısından belirgin biçimde daha iyidir.

**Ek uyarı:** Gözlenen ekranlar **eski build**e aittir (bkz. A.0). Bunlar güncel kaynağın değil, canlıdaki önceki sürümün kanıtıdır. Güncel kaynağın runtime kanıtı ancak `careoncloud-v0.1.0` imajı aday portta ayağa kaldırılırsa üretilebilir. Buna rağmen `Layout.pm:4221`, `D724KPIGrid`, `onchange`, ham durum değerleri ve boş `lang` gibi bulgular **güncel kaynakta da** doğrulanmıştır — bunları cutover çözmez.

## B.6 Varsayımlar

| # | Varsayım | Durum |
|---|---|---|
| V1 | Kullanıcının tarif ettiği agent dashboard görüntüsü bu eski canlı dağıtıma aittir | **Doğrulandı** — dashboard birebir gözlendi |
| V2 | `PANO` / `TAKVİM` / `BİLETLER` çekirdek TR sözlüğünden gelir | **Doğrulandı** — `Kernel/Language/tr.pm:2967, 156, 3069`. Not: gözlenen oturum EN olduğu için menüde İngilizce adlar çıktı; TR oturumda bu ALL-CAPS adlar görünür. |
| V3 | Canlı DB, `careoncloud_esm` değil eski şemadır | **Kısmen doğrulandı** — `Welcome to CareOnCloud ESM!` ve 2015 tarihli örnek kayıt mevcut; DB adı doğrulanmadı |
| V4 | Agent dashboard'daki boş tablolar CareOnCloud ESM varsayılan widget'larıdır | **Doğrulandı** — 8 widget'ın tamamı CareOnCloud ESM varsayılanı, 4'ü boş |
| V5 | Demo tenant'larındaki gerçek şirket adlarına bu kurumlardan izin alınmamıştır | **Doğrulanmalı** — ürün sahibinden teyit gerekir (K-9) |

---

# C. UX skor kartı

0 = yok · 1 = kritik kusurlu · 2 = zayıf · 3 = kabul edilebilir · 4 = iyi · 5 = örnek

| # | Alan | Puan | Kanıt / gerekçe |
|---|---|---|---|
| 1 | Marka bütünlüğü | **1** | Müşteri giriş ekranında `Your Tickets. Your OTOBO.` (`Layout.pm:4221`) + OTOBO tavus kuşu. `Framework.xml:8726,8763,9267` → otobo.io RSS, otobo.io CDN görseli, `HomePage www.otobo.io`. Canlıda tüm yollar `/otobo/`. Karşı ağırlık: login başlığı ve logo doğru. |
| 2 | Bilgi mimarisi | **1** | D724 modülleri çekirdek CareOnCloud ESM menüsüne **düz** eklenmiş. Hiyerarşi yok, gruplama yok. `Service Portfolio`, `Operations Center`, `D724 Requests`, `Change Enablement`, `Problem Management`, `Agent Assistant` — altısı da `Type: Menu`, aynı düzeyde, `Prio` 75–87 arası. Kullanıcıya "hizmet" mi "kayıt" mı yönettiği anlatılmıyor. |
| 3 | Navigasyon | **1** | Çekirdek CareOnCloud ESM menüsü (`PANO`, `BİLETLER`, `TAKVİM`, `Müşteriler`, `Queue view`, `Escalation view`, `Status view`, `Service view`…) ile D724 menüleri yan yana. AccessKey çakışması: `p` hem `Service Portfolio` hem `Problem Management` (`D724CMDB.xml`, `D724Problem.xml`). |
| 4 | Görev tamamlama | **2** | Katalogdan talep açma **çalışıyor** ve idempotency korumalı. Ancak müşteri sonrasında talebi göremiyor; agent tarafında liste/filtre/arama yok, sayfalama yok. |
| 5 | Rol bazlı deneyim | **1** | 6 personadan 3'ünün (admin, MSP, denetçi) hiç ekranı yok. Agent ile hizmet sahibi aynı `Operations Center`'ı paylaşıyor. Müşterinin tek menü öğesi var. |
| 6 | TR/EN bütünlüğü | **1** | **OBSERVED:** tek ekranda İngilizce widget başlıkları + Türkçe kolon adları + çevrilmemiş `Total`; `Kuyruğa koy` yanlış çeviri; `YENI` bozuk büyük harf; `87.5%` ve `2026-07-27 08:45:00` yerelleştirilmemiş. TR çeviri sayıları: Reporting 40, Catalog 11, Request 7, Assist/CMDB/Change 3'er, **Commitment 1, Problem 1**. Buna karşılık aynı paketlerin XML'lerinde 16 ve 8 `Translatable` metin var. Katalog form etiketleri `[% Data.label %]` ile çevrilmeden basılıyor. Durum değerleri (`in_progress`, `approved`, `rejected`) ham makine değeri olarak ekrana geliyor. |
| 7 | İçerik / mikro metin | **1** | Menüde `D724 Requests` (kod adı, kullanıcıya görünür). `Service extension` / `Servis uzantısı` — kullanıcı için anlamsız, üstelik kanonik modeldeki `Service Offering` karşılığı değil. `Technical key` alanı son kullanıcı rapor formunda. `AgentD724Request.tt` içinde çevrilmeyen ` — assigned: ` metni. |
| 8 | Görsel hiyerarşi | **1** | D724 paketlerinde **hiç CSS yok**. `AgentD724Operations.tt:30` `class="D724KPIGrid"` ve `class="D724KPI"` kullanıyor; bu sınıflar **hiçbir yerde tanımlı değil** (repo genelinde yalnızca bu şablonda geçiyor). Yani KPI ızgarası ızgara olarak render olmuyor, alt alta widget'a düşüyor. |
| 9 | Form kullanılabilirliği | **1** | **Müşteri/agent tarafı ile admin tarafı çok farklı.** Müşteri şablonlarında `<label for>` bağları doğru; `required`, `maxlength`, `ChallengeToken` CSRF ve `ExpectedVersion` optimistic locking var. **Admin tarafında ise `AdminD724Catalog.tt` 0 `<label>` / 9 `placeholder`, `AdminD724Commitment.tt` 1 `<label>` / 5 `placeholder`** içeriyor; `CalendarID` ve `WarningPercent` alanlarının ne etiketi ne placeholder'ı var. SLA politikası ham JSON textarea'sı. Alan bazlı hata mesajı, yardım metni ve geri alınamaz eylemlerde onay adımı hiçbir yerde yok. |
| 10 | Veri yoğun ekran ergonomisi | **1** | `class="DataTable"` düz tablolar. Sıralama, filtre, sütun seçimi, toplu işlem, kaydedilmiş görünüm, sayfalama **yok**. `D724::CMDB::ListLimit` 1000, `Change/Problem ListLimit` 200 — sayfalama olmadan tek sayfaya basılıyor. |
| 11 | Responsive kullanım | **2** | Login mobilde temiz (taşma yok, 48px hedef). D724 ekranları için `NEEDS_ACCESS`; ancak sayfalama/kaydırma kabı olmayan geniş tablolar mobilde yatay taşma üretir — kaynaktan öngörülebilir risk. |
| 12 | WCAG 2.2 AA uyumu | **1** | Doğrulanmış ihlaller: `<html lang="">` boş — **1.3.1/3.1.1 (A)**. `<select onchange="this.form.submit()">` (`AgentD724Request.tt:6`) — **3.2.2 On Input (A)**. AccessKey çakışması — **2.1.1 destekleyici**. Renk kontrastı ve focus görünürlüğü `NEEDS_ACCESS`. |
| 13 | Hata / boş / yükleme durumları | **0** | 10 D724 şablonunun **hiçbirinde** boş durum metni yok; `[% RenderBlockStart %]` blokları veri yoksa hiçbir şey basmıyor. **OBSERVED:** `AgentD724Request`'te eylem yokken hiçbir açıklama çıkmıyor. Çekirdek CareOnCloud ESM en azından `none` yazıyor — yani D724 ekranları bu konuda **mirastan da geride**. Skeleton/yükleme yok. |
| 14 | Tenant / MSP bağlam görünürlüğü | **1** | `AgentD724Request.tt:7` tenant seçeneğini **ham `TenantID`** ile basıyor (`>[% Data.TenantID %]<`), oysa `AgentD724Operations.tt` aynı yerde `Data.Name` kullanıyor — tutarsız. Seçim `onchange` ile anında formu gönderiyor; yanlış tenant'a kazara geçiş mümkün. Global bir tenant göstergesi yok. |
| 15 | Güven / kurumsal ürün algısı | **1** | Müşterinin ilk gördüğü ekranda başka bir ürünün adı. Adres çubuğunda `/careoncloud/`. Agent dashboard'unda `Welcome to CareOnCloud ESM!` test kaydı. Bu üçü bir arada satın alma görüşmesinde ürünü "başkasının ürününün üstüne isim yapıştırılmış" konumuna düşürür. |

**Ağırlıksız ortalama: 1.13 / 5**

---

# D. As-is ekran ve yolculuk haritası

## D.1 Ekran envanteri

`NEEDS_ACCESS` = kaynaktan biliniyor, çalışır hâlde görülmedi.

### Müşteri yüzeyi

| Ekran / rota | Rol | Kullanıcı amacı | UI teknolojisi | Dil | Marka | UX durumu | Kanıt | Karar |
|---|---|---|---|---|---|---|---|---|
| `customer.pl` (login) | Müşteri | Giriş | Core TT + Customer skin | EN, seçici yok | **CareOnCloud ESM sloganı + görseli** | Kritik kusurlu | OBSERVED | **Değiştir** |
| `CustomerD724Catalog` | Müşteri | Hizmet bul, talep tipi seç | D724 TT, kendi CSS'i yok | TR 11 anahtar | CareOnCloud | Sürtünmeli | VERIFIED_IN_SOURCE | **İyileştir** |
| `CustomerD724Catalog?Subaction=Item` | Müşteri | Dinamik form doldur | D724 TT | Form etiketleri **çevrilemiyor** | CareOnCloud | Sürtünmeli | VERIFIED_IN_SOURCE | **İyileştir** |
| `CustomerD724Request` (Submit) | Müşteri | Talep gönder, makbuz gör | D724 TT | Durum ham değer | CareOnCloud | Kritik kusurlu | VERIFIED_IN_SOURCE | **Değiştir** |
| **Talep listesi / takip** | Müşteri | Açık talebini izle | — | — | — | **YOK** | VERIFIED_IN_SOURCE | **Yeni yap** |
| Core `CustomerTicketOverview` | Müşteri | CareOnCloud ESM ticket'ları | Core TT | `BİLETLER` | CareOnCloud ESM terminolojisi | Sürtünmeli, D724 talebiyle **ilişkisiz** | VERIFIED_IN_SOURCE | **Sar / ayrıştır** |

### Agent yüzeyi

| Ekran / rota | Rol | Amaç | UI teknolojisi | Dil | Marka | UX durumu | Kanıt | Karar |
|---|---|---|---|---|---|---|---|---|
| `index.pl` (login) | Agent | Giriş | Core TT + Agent skin | EN, seçici yok | CareOnCloud logo ✓ | Sürtünmeli | OBSERVED | **İyileştir** |
| `AgentDashboard` | Agent | Günü başlat | Core TT | `PANO` | otobo.io RSS widget'ı | Kritik kusurlu | VERIFIED_IN_SOURCE | **Değiştir** |
| `AgentD724Request` | Agent | Onay, görev, ilk yanıt | D724 TT | Ham durumlar, `assigned:` | `D724 Requests` başlığı | Kritik kusurlu | VERIFIED_IN_SOURCE | **Değiştir** |
| `AgentD724Operations` | Agent / Hizmet sahibi | KPI, rapor | D724 TT, tanımsız CSS sınıfı | TR 40 anahtar (en iyi paket) | CareOnCloud | Sürtünmeli | VERIFIED_IN_SOURCE | **İyileştir** |
| `AgentD724ServicePortfolio` | Agent | Hizmet portföyü | D724 TT | TR 3 anahtar | CareOnCloud | Eksik | VERIFIED_IN_SOURCE | **İyileştir** |
| `AgentD724Change` | Agent | Değişiklik | D724 TT | TR 3 anahtar | CareOnCloud | Prototip | VERIFIED_IN_SOURCE | **Koru (dondur)** |
| `AgentD724Problem` | Agent | Problem | D724 TT | TR **1** anahtar | CareOnCloud | Prototip | VERIFIED_IN_SOURCE | **Koru (dondur)** |
| `AgentD724Assist` | Agent | Benzer kayıt önerisi | D724 TT | TR 3 anahtar | `Agent Assistant` | Prototip | VERIFIED_IN_SOURCE | **İyileştir (yeniden adlandır)** |
| Core ticket ekranları | Agent | Kayıt işlemek | Core TT | `BİLETLER` | CareOnCloud ESM terminolojisi | Sürtünmeli | NEEDS_ACCESS | **Sar / adapter** |

### Admin, MSP, denetçi yüzeyi

| Ekran | Rol | Durum | Kanıt |
|---|---|---|---|
| `AdminD724Catalog` | Admin | Var; **tablosuz satır-içi form yığını**, 0 `<label>`, 51 offering tek sayfada, test artefaktı görünür | **OBSERVED** + VERIFIED_IN_SOURCE |
| `AdminD724Commitment` | Admin | Var; **SLA politikası ham JSON textarea**, 1 `<label>`, açıklamasız sayı alanları, yinelenen durum seçeneği | **OBSERVED** + VERIFIED_IN_SOURCE |
| Tenant Directory yönetimi | Admin / MSP | **YOK** | VERIFIED_IN_SOURCE |
| TenantGuard politika görünürlüğü | Admin | **YOK** | VERIFIED_IN_SOURCE |
| Identity / OIDC yönetimi | Admin | **YOK** | VERIFIED_IN_SOURCE |
| SCIM sağlayıcı durumu | Admin | **YOK** | VERIFIED_IN_SOURCE |
| Webhook yönetimi / dead-letter | Admin | **YOK** | VERIFIED_IN_SOURCE |
| API istemci / token yönetimi | Admin | **YOK** | VERIFIED_IN_SOURCE |
| **Audit inceleme ve kanıt dışa aktarımı** | Denetçi | **YOK** | VERIFIED_IN_SOURCE |
| MSP tenant panosu | MSP | **YOK** | VERIFIED_IN_SOURCE |

Bu tablo A.1'deki "üç persona ekransız" iddiasının kanıtıdır: `packages/*/Kernel/Modules/` altında 13 modül vardır ve bunların hiçbiri tenant, identity, SCIM, webhook veya audit yönetim ekranı değildir.

## D.2 Mevcut navigasyon ağacı (as-is)

```
Agent üst menü (çekirdek + D724 karışık, tek düzey)
├── PANO                        ← tr.pm:2967, ALL CAPS
├── BİLETLER                    ← tr.pm:3069, ALL CAPS
│   ├── Queue view / Status view / Escalation view / Service view
│   ├── Search
│   └── New phone ticket / New email ticket
├── Müşteriler                  ← tr.pm:483
├── TAKVİM                      ← tr.pm:156, ALL CAPS
│   └── Agenda Overview
├── Agent Assistant      (Prio 75, AccessKey a)   ← TR adı yok
├── Operations Center    (Prio 80, AccessKey o)   ← TR adı yok
├── Service Portfolio    (Prio 85, AccessKey p)   ← ÇAKIŞMA
├── Change Enablement    (Prio 86, AccessKey h)   ← TR adı yok
├── Problem Management   (Prio 87, AccessKey p)   ← ÇAKIŞMA
├── D724 Requests        (AccessKey r)            ← KOD ADI GÖRÜNÜR
└── Yönetim (Admin)

Müşteri portalı menü
└── Service Catalog     ← tek öğe. "Taleplerim" yok.
```

Üç yapısal kusur:

1. **Karışım.** Türkçe ALL-CAPS çekirdek adlar, İngilizce D724 adları ve bir kod adı (`D724`) aynı çubukta.
2. **Düzlük.** Altı D724 modülü de kök düzeyde. Kullanıcı hangisinin "iş yapma", hangisinin "izleme", hangisinin "yönetim" olduğunu ayırt edemiyor.
3. **Çift kayıt kavramı.** `BİLETLER` (CareOnCloud ESM ticket) ile `D724 Requests` (D724 request) paralel iki iş nesnesi. `packages/D724Request` içinde `TicketObject` referansı **hiç yok** — yani bu iki dünya kodda da bağlı değil. Agent aynı işi iki yerden takip ediyor.

## D.3 Kritik yolculukların mevcut durumu

| # | Yolculuk | Mevcut durum | En ağır sürtünme |
|---|---|---|---|
| 1 | Müşteri katalogdan talep açar | **Çalışıyor** | 3 ardışık `<select>`, arama yok, hizmet açıklaması ancak seçtikten sonra görünüyor |
| 2 | Müşteri talebini takip eder | **YOK** | Ekran yok. Gönderim sonrası tek makbuz sayfası. |
| 3 | Agent SLA riskli işi önceliklendirir | **Kısmi** | `AgentD724Request` tüm talepleri sırasız basıyor; sıralama/filtre yok |
| 4 | Agent kaydı açar, çözer | **Bölünmüş** | D724 request tarafında iletişim/not/ek yok; ticket tarafında SLA/onay yok |
| 5 | Onaylayıcı onaylar/reddeder | **Çalışıyor, riskli** | Onay ve ret aynı formda yan yana buton, geri dönüşsüz, onay adımı yok |
| 6 | Hizmet sahibi SLA performansı inceler | **Kısmi** | Operations Center tablo tabanlı, grafik yok, sıfır-veri davranışı tanımsız |
| 7 | Admin katalog/rol/entegrasyon yapılandırır | **Kısmi** | Katalog ve commitment var; rol, kimlik, entegrasyon ekranı yok |
| 8 | MSP tenant değiştirip performans inceler | **Kritik kusurlu** | Ham `TenantID`, `onchange` anında gönderim, global bağlam göstergesi yok |
| 9 | Denetçi olay zinciri filtreler, kanıt aktarır | **YOK** | Ekran yok; yalnızca CLI/API |
| 10 | Kullanıcı dil ve saat dilimi seçer | **NEEDS_ACCESS** | Login ekranında dil seçici yok; `<html lang="">` boş |

---

# E. Bulgular backlog'u

**Önem:** `P0` pilot kapısı · `P1` iş akışını ciddi yavaşlatır · `P2` verimlilik/tutarlılık · `P3` farklılaşma

| ID | Kanıt | Rol | Ekran / yolculuk | Sorun | Etki | Önem | Kök neden | Öneri | Bağımlılık | Kabul kriteri |
|---|---|---|---|---|---|---|---|---|---|---|
| P0-01 | OBSERVED + `Layout.pm:4221` | Müşteri | Müşteri login | `Your Tickets. Your CareOnCloud ESM.` başlığı + CareOnCloud ESM tavus kuşu arka planı | Marka ihlali; ilk izlenim başka ürün | P0 | Hardcoded fallback + `CustomerLogin::Settings` boş | Fallback'i çevrilebilir CareOnCloud metnine çevir; `LoginBG.jpg`'i değiştir | — | `curl customer.pl` çıktısında `CareOnCloud ESM` geçmez; TR ve EN'de doğru slogan |
| P0-02 | OBSERVED | Hepsi | Tüm rotalar | Canlıda `/careoncloud/index.pl`, `/otobo-web/` | Marka ihlali, adres çubuğunda görünür | P0 | Cutover yapılmadı; kaynak zaten doğru | `careoncloud-v0.1.0` imajını aday portta ayağa kaldır, kabul sonrası kes | Rollback provası | `/careoncloud/index.pl` 200; `/careoncloud/*` 404 veya 301 |
| P0-03 | `Framework.xml:8726,8727,8763,9267` | Agent | Dashboard | otobo.io RSS widget'ı, otobo.io CDN görseli, `HomePage www.otobo.io` | Marka ihlali + müşteri ortamından dışa istek | P0 | Upstream varsayılanları temizlenmemiş | Widget'ları kaldır veya CareOnCloud kaynağına yönlendir | — | Dashboard HTML'inde `otobo.io` geçmez; giden istek yok |
| P0-04 | `Test-CareOnCloudBrand.ps1:38-53` | — | CI | Marka testi yalnız dosya yolu tarıyor, render metnini taramıyor | P0-01 testlerden geçti | P0 | Test tasarımı eksik | Şablon+Perl string taraması ekle: `Layout.pm`, `*.tt`, `Framework.xml` | — | Test, `Layout.pm:4221` geri konursa **kırmızı** olur |
| P0-05 | VERIFIED_IN_SOURCE | Müşteri | Talep takibi | `CustomerD724Request` yalnızca `Submit`; liste/detay yok | Müşteri talebini göremiyor → portal kullanılamaz | P0 | Ekran hiç yazılmamış | `Taleplerim` listesi + talep detay/timeline ekranı | Request read API | Müşteri gönderdiği talebi listede görür; durum, sorumlu, hedef süre görünür |
| P0-06 | `AgentD724Request.tt:6-7` **ve** `AdminD724Commitment.tt:4-5`; ikisi de OBSERVED | Agent / MSP / Admin | Tenant seçimi | Ham `TenantID` + `onchange="this.form.submit()"` — **iki ayrı ekranda** | Yanlış tenant'a kazara geçiş; WCAG 3.2.2 (A) | P0 | Hızlı prototip | Tenant adını göster; açık `Uygula` butonu; global tenant rozeti | TenantDirectory ad alanı | Seçim adla yapılır; otomatik gönderim yok; aktif tenant her ekranda görünür |
| P0-07 | 8 `tr_*.pm` sayımı | Hepsi | Tüm D724 ekranları | Commitment 1, Problem 1 çeviri; XML'de 16 ve 8 çevrilebilir metin | Türkçe kullanıcı İngilizce ekran görür | P0 | Çeviri tamamlanmamış | Kanonik TR/EN sözlüğü + eksik anahtarları doldur | F.4 sözlüğü | Her D724 ekranı TR'de %100 çeviri; karışık dil yok |
| P0-08 | `AgentD724Request.tt`, `CustomerD724Request.tt` | Hepsi | Durum gösterimi | `in_progress`, `approved`, `rejected` ham makine değeri | Kullanıcı durumu anlamıyor; iki dil bozuluyor | P0 | `Translate()` uygulanmamış | Durum değerlerini sözlüğe al, `Translate(Data.Status)` kullan | P0-07 | TR'de "Devam ediyor", EN'de "In progress" |
| P0-09 | OBSERVED | Hepsi | Tüm sayfalar | `<html lang="">` boş | WCAG 2.2 **3.1.1 (A)** ihlali; ekran okuyucu yanlış telaffuz | P0 | Layout `lang` basmıyor | Aktif kullanıcı diline göre `lang` yaz | — | TR oturumda `lang="tr"`, EN'de `lang="en"` |
| P0-10 | VERIFIED_IN_SOURCE | Denetçi | Audit | Audit inceleme/dışa aktarım ekranı yok | Denetçi personası kullanılamaz; regüle müşteride kapı | P0 | Ekran yazılmamış | Audit tarama + filtre + kanıt paketi ekranı | Audit read API | Denetçi tarih/tenant/aktör filtreler, imzalı paket indirir |
| **P0-11** | OBSERVED — tenant seçicisi. **Kaynakta yok** (bkz. düzeltme notu) | Hepsi | Demo verisi | **~40 gerçek Türk şirketinin adı canlı ortamda demo tenant olarak kayıtlı** (`demo-anadolu-hayat-emeklilik`, `demo-i-s-bankasi-almanya`, `demo-qnb-finans`, `demo-milli-reasurans`, `demo-mavi`, `demo-setur`, `demo-bkm`, `demo-i-stanbul-modern-eczacibasi-bilisim` …) | Hukuki ve itibari risk; demo sırasında rakip/müşteri adının görünmesi; Master Context §13.4 açık yasağı | **P0** | **Eski canlı DB verisi.** Güncel kaynaktaki üç seed script'i tamamen sentetik ad kullanıyor; bu kayıtlar onlardan üretilmemiş | Canlı DB'deki bu tenant'ları ve bağlı veriyi temizle; güncel sentetik seed'i çalıştır; CI'ya yasaklı isim taraması ekle | Demo DB temizliği | Tenant listesinde hiçbir gerçek kurum adı yok; isim taraması yeşil |
| **P0-16** | OBSERVED — `AgentPreferences` | Hepsi | Tercihler | Dil ayarının altında *"You can help translating **OTOBO** at translate.otobo.org"* + dış bağlantı | Her kullanıcının gittiği ekranda marka ihlali ve rakip projeye yönlendirme | **P0** | Upstream metni temizlenmemiş | Metni ve bağlantıyı kaldır | J2 taraması | Tercihler ekranında `otobo` geçmez |
| **P0-17** | OBSERVED — dil listesi | Hepsi | Tercihler | Dil seçicide **"Türkçe - Turkish (in process)"** yazıyor; ayrıca 50 dil listeleniyor | Ana pazarı Türkiye olan üründe dil seçici Türkçeyi "tamamlanmamış" ilan ediyor; desteklenmeyen 48 dile geçen kullanıcı bozuk ürün görüyor | **P0** | Upstream tamamlanma etiketi + dil listesi kısıtlanmamış | Listeyi `Türkçe` ve `English` ile sınırla; `(in process)` etiketini kaldır | P0-07 çeviri tamamlanması | Dil seçicide yalnız TR ve EN var; hiçbirinde "in process" yazmıyor |
| **P0-18** | OBSERVED — `AgentPreferences` | Hepsi | Saat dilimi | Varsayılan saat dilimi **UTC**; `Europe/Istanbul` mevcut ama seçili değil | Her yeni kullanıcı yanlış saat görüyor ve P0-14 banner'ını yiyor | **P0** | Varsayılan yapılandırılmamış | Kurulum varsayılanını `Europe/Istanbul` yap; onboarding'de sor | — | Yeni kullanıcıda banner çıkmaz; saatler doğru |
| P2-07 | OBSERVED — `AgentPreferences` | Hepsi | Avatar | Gravatar'a kullanıcı e-postasıyla dış istek öneriliyor | Kurumsal/regüle müşteride veri çıkışı sorusu | P2 | Upstream varsayılanı | Gravatar'ı kapat veya yerel avatar yükleme sun | Hukuk | Tercihler ekranında dış servise e-posta gönderimi önerilmez |
| **P0-12** | OBSERVED — `AgentD724Request` | Agent | Talep ekranı | Talep sahibi 64 karakterlik hash olarak gösteriliyor (`customer:925bd03220…`) | Agent talebi kimin açtığını göremiyor → temel görev imkânsız | **P0** | Requester ID çözümlenmiyor | Ad, soyad, organizasyon ve iletişim bilgisi göster; hash yalnız teknik alanda | Customer directory lookup | Ekranda kişi adı görünür; hash görünmez |
| **P0-13** | OBSERVED — dashboard | Hepsi | Tüm sayfalar | `yeni` → **`YENI`** (noktasız I). CSS `text-transform: uppercase`, boş `lang` nedeniyle Türkçe kuralı uygulamıyor | Türkçe metin görsel olarak bozuk; kurumsal algı | **P0** | P0-09'un doğrudan sonucu | `lang` düzeltilir; ayrıca menü/kolon `text-transform: uppercase` kuralı kaldırılır | P0-09 | TR oturumda `YENİ` doğru yazılır; ALL-CAPS kaldırılır |
| P0-14 | OBSERVED — her sayfa | Agent | Global banner | *"Please select a time zone in your preferences…"* İngilizce, kalıcı, her sayfada | İlk izlenimde yabancı dil; kapatılamayan gürültü | P0 | Kullanıcı saat dilimi seçmemiş; uyarı çevrilmemiş/yerelleştirilmemiş | Onboarding'de saat dilimi sor; uyarıyı çevir ve kapatılabilir yap | P0-07 | TR oturumda Türkçe; seçim sonrası kaybolur |
| **P0-15** | OBSERVED + `AdminD724Catalog.tt` (0 `<label>` / 9 `placeholder`), `AdminD724Commitment.tt` (1 `<label>` / 5 `placeholder`) | Admin | Her iki admin ekranı | Form alanlarının neredeyse tamamında `<label>` yok; bazılarında `placeholder` da yok (`0`, `14400`, `80` açıklamasız) | Ekran okuyucu kullanıcısı ekranı kullanamaz; gören kullanıcı da alanların ne olduğunu bilemez | **P0** | Hızlı prototip; erişilebilirlik hiç ele alınmamış | Her alana `<label for>`, birim ve yardım metni ekle | — | `axe-core` `label` kuralı geçer; her sayısal alanda birim yazar |
| **P1-10** | OBSERVED — `AdminD724Commitment` | Admin | SLA politikası | SLA/OLA hedefleri ham JSON `<textarea>` içinde elle yazılıyor; doğrulama geri bildirimi yok | Ürünün en önemli ticari özelliği yalnızca JSON yazabilen kişilerce yapılandırılabiliyor; yazım hatası sessizce kabul edilebilir | P1 | Editör yazılmamış | Hedef/uyarı/sinyal alanları için yapılandırılmış form; JSON "gelişmiş" sekmesine | Commitment şeması | Yönetici JSON yazmadan SLA tanımlar; hatalı giriş alan bazlı hata verir |
| **P1-11** | OBSERVED — katalog | Hepsi | Demo verisi | Atomiklik testinden kalma kayıtlar ürün kataloğunda (`Atomic Audit Service Update`, `atomic-audit-offering`, `draft`) | Demo sırasında ürün "temizlenmemiş" görünüyor | P1 | Test verisi demo DB'sinden silinmemiş | Test artefaktlarını temizle; test verisi ayrı tenant'ta üretilsin | J6b | Demo kataloğunda test kaydı yok |
| **P1-12** | `AdminD724Commitment.tt` PolicyRow | Admin | Durum seçici | Mevcut değer ilk seçenek olarak eklenip `active`/`inactive` de listeleniyor → `active, active, inactive` | Yinelenen seçenek; yanlış seçim riski | P1 | Şablon hatası | Mevcut değeri `selected` ile işaretle, tekrar ekleme | — | Açılır listede yinelenen seçenek yok |
| P1-01 | `CustomerD724Catalog.tt` | Müşteri | Katalog | Etiketler `Service category` / `Servis uzantısı`; kanonik model `Service` / `Service Offering` | Kullanıcı ve ekip farklı kavram konuşuyor | P1 | Master Context §3.2'deki semantik çakışma UI'ya sızmış | Terminolojiyi kanonik modele çek | Katalog veri modeli kararı (K-2) | UI etiketleri = kanonik model; `Servis uzantısı` kalmaz |
| P1-02 | `CustomerD724Catalog.tt` FormField | Müşteri | Dinamik form | `[% Data.label %]` çevrilmeden basılıyor | Katalog içeriği tek dilde kalıyor | P1 | Form şeması dil taşımıyor | Form şemasına `label_tr` / `label_en` ekle | Katalog şema sürümleme | Aynı katalog öğesi TR ve EN'de doğru etiketle açılır |
| P1-03 | 10 şablonun tamamı | Hepsi | Tüm listeler | Hiçbir şablonda boş durum yok | Kullanıcı boş beyaz alanı hata sanıyor | P1 | Blok render veri yoksa hiçbir şey basmıyor | Her liste için boş durum bileşeni + eylem önerisi | Tasarım sistemi | Veri yokken açıklayıcı metin + birincil eylem görünür |
| P1-04 | `AgentD724Operations.tt:30-34` **+ OBSERVED** (`display:block`, `grid-template-columns:none`, `.D724KPI` 16 px) | Agent | Operations Center | `D724KPIGrid` / `D724KPI` sınıfları hiçbir yerde tanımlı değil | KPI'lar ızgara olmuyor, alt alta düşüyor; KPI rakamı gövde metniyle aynı boyutta | P1 | Pakette CSS yok, loader kaydı yok | D724 ortak CSS dosyası + `Loader::Agent::CommonCSS` kaydı | Tasarım sistemi | KPI'lar 4'lü ızgarada; 1280/768/375'te doğru |
| P1-05 | `D724CMDB.xml`, `D724Problem.xml` | Agent | Navigasyon | AccessKey `p` iki modülde | Klavye kısayolu belirsiz | P1 | Koordinasyonsuz atama | Benzersiz AccessKey matrisi | — | Kaynakta AccessKey tekrarı yok (CI kontrolü) |
| P1-06 | `AgentD724Request.tt` | Agent | Onay | `Onayla` / `Reddet` yan yana, geri dönüşsüz, onay yok | Yanlış tıklama ile hatalı karar | P1 | Prototip form | Ret için zorunlu gerekçe + onay adımı; butonları görsel olarak ayır | Tasarım sistemi | Ret gerekçesiz gönderilemez; onay adımı var |
| P1-07 | `AgentD724Request.tt` | Agent | İş listesi | Sıralama, filtre, arama, sayfalama yok | SLA riskli iş görünmüyor | P1 | Liste ekranı yazılmamış | Filtre + kaydedilmiş görünüm + SLA'ya göre sıralama | Request query API | Agent "SLA riski" görünümünü tek tıkla açar |
| P1-08 | `AgentD724Operations.tt` | Hizmet sahibi | Rapor | `Technical key` alanı son kullanıcıya açık | Teknik sızıntı, hata riski | P1 | Admin alanı son kullanıcı formunda | Otomatik türet veya gelişmiş bölüme al | — | Rapor kaydetmede teknik anahtar sorulmaz |
| P1-09 | `AgentD724Request.tt` | Agent | Görev satırı | ` — assigned: ` çevrilmemiş sabit metin | Karışık dil | P1 | `Translate()` unutulmuş | Çevrilebilir yap | P0-07 | Kaynakta çevrilmemiş kullanıcı metni yok (CI taraması) |
| P2-01 | Nav XML'leri | Hepsi | Navigasyon | 6 D724 modülü düz, gruplanmamış | Öğrenilebilirlik düşük | P2 | Gruplama tasarlanmamış | F.1'deki rol bazlı ağaç | IA kararı | Menü en fazla 2 düzey; her öğe bir role ait |
| P2-02 | `tr.pm:156,2967,3069` | Hepsi | Menü | `PANO`, `TAKVİM`, `BİLETLER` ALL CAPS | Bağırıyor, kurumsal algıyı düşürüyor | P2 | Upstream TR sözlüğü | `Pano`→`Ana sayfa`, `TAKVİM`→`Takvim`, `BİLETLER`→`Kayıtlar` | Terim sözlüğü | Menüde ALL-CAPS Türkçe yok |
| P2-03 | `D724::CMDB::ListLimit` 1000 | Agent | Listeler | Sayfalama yok, 1000 satır tek sayfa | Yavaş sayfa, mobilde kullanılamaz | P2 | Sayfalama yazılmamış | Sayfalama + sunucu tarafı filtre | — | Sayfa başına ≤50 satır; mobilde yatay taşma yok |
| P2-04 | OBSERVED | Hepsi | Login | Cloudflare Insights beacon, `js/ads.js` | Üçüncü taraf istek, rıza yok; `ads.js` CareOnCloud ESM adblock tespiti | P2 | Upstream + altyapı varsayılanı | `ads.js` kaldır; beacon'ı KVKK açısından değerlendir | Hukuk | Login sayfasında rızasız üçüncü taraf istek yok |
| P2-05 | Nav XML'leri | Agent | Adlandırma | `Agent Assistant`, `Operations Center`, `Service Portfolio` TR adı yok | Karışık dil | P2 | Çeviri yok | `Destek Asistanı`, `Operasyon Merkezi`, `Hizmet Portföyü` | F.4 | TR oturumda menüde İngilizce ad yok |
| P2-06 | `D724Request` ↔ ticket | Agent | Kayıt modeli | Request ve ticket kodda bağlantısız | Agent iki yerde çalışıyor | P2 | Tasarım kararı verilmemiş | K-1 kararı sonrası birleştirme veya net ayrım | K-1 | Agent tek çalışma alanından iş yürütür |
| P3-01 | — | Agent | Klavye | Global komut paleti yok | Uzman verimliliği | P3 | — | `Ctrl+K` hızlı eylem | Yeni kabuk | Agent klavyeden kayıt açar/arar |
| P3-02 | — | Hizmet sahibi | Rapor | Grafik yok | Trend okunamıyor | P3 | Grafik katmanı yok | Sıfır-veri davranışı tanımlı grafik bileşeni | Tasarım sistemi | Veri yokken grafik "veri yok" durumu gösterir |

---

# F. Hedef bilgi mimarisi

## F.1 Prensipler

1. **Rol ana sayfayı belirler.** Aynı `/careoncloud/` altında her rol farklı bir varsayılan ekrana düşer.
2. **En fazla iki düzey.** Kök menü öğesi sayısı role göre 4–6.
3. **Teknik kod adı menüde görünmez.** `D724` yalnızca namespace'te kalır.
4. **Tenant bağlamı menüde değil, global başlıkta durur** ve her sayfada görünür.
5. **Her kök öğe bir soruya cevap verir:** "Ne yapacağım?" / "Ne durumda?" / "Nasıl ayarlanır?"

## F.2 Rol bazlı hedef menü ağaçları

### Müşteri / hizmet alan

| TR | EN | Not |
|---|---|---|
| **Ana sayfa** | **Home** | Açık taleplerim + hızlı katalog araması |
| **Hizmet al** | **Get help** | Katalog (arama önce, ağaç sonra) |
| **Taleplerim** | **My requests** | Açık / bekleyen onay / kapanan (**bugün yok — P0-05**) |
| **Bilgi** | **Knowledge** | Makale arama (P2) |
| *(profil menüsü)* | | Dil · Saat dilimi · Bildirimler · Çıkış |

### Agent / uzman

| TR | EN | Alt öğeler |
|---|---|---|
| **Bugün** | **Today** | Bana atananlar · SLA riski · Onayımı bekleyen · Yaklaşan görevler |
| **İş listesi** | **Work queue** | Kuyruklar · Kaydedilmiş görünümler · Arama |
| **Hizmetler** | **Services** | Hizmet portföyü · Katalog görünümü · CI/varlık |
| **İyileştirme** | **Improvement** | Problem · Değişiklik *(P2'ye kadar gizli)* |
| **Destek Asistanı** | **Assist** | Benzer çözülmüş kayıtlar |

### Hizmet sahibi

| TR | EN | Alt öğeler |
|---|---|---|
| **Hizmet sağlığı** | **Service health** | SLA uyumu · İhlaller · Trend |
| **Talep hacmi** | **Demand** | Katalog öğesine göre · Dönem karşılaştırma |
| **Hizmet portföyü** | **Service portfolio** | Sahiplik · Kritiklik · Kapsam |
| **Raporlar** | **Reports** | Kaydedilmiş raporlar · Dışa aktarım |

### Platform yöneticisi

| TR | EN | Alt öğeler |
|---|---|---|
| **Katalog** | **Catalog** | Hizmet ağacı · Katalog öğeleri · Formlar · Yayın durumu |
| **Taahhütler** | **Commitments** | SLA/OLA · Takvimler · Duraklama kuralları |
| **Kimlik ve erişim** | **Identity & access** | Kullanıcılar · Roller · OIDC · SCIM *(**bugün yok**)* |
| **Entegrasyon** | **Integrations** | API istemcileri · Webhook · Dead-letter *(**bugün yok**)* |
| **Platform** | **Platform** | Bildirimler · Genel ayarlar · Sağlık |

### MSP yöneticisi

| TR | EN | Alt öğeler |
|---|---|---|
| **Müşteriler** | **Customers** | Tenant listesi · Sözleşme · Entitlement *(**bugün yok**)* |
| **Hizmet kalitesi** | **Service quality** | Tenant kırılımlı SLA |
| **Operasyon** | **Operations** | Tenant'lar arası yük ve kapasite |
| *(global)* | | **Aktif müşteri rozeti — her sayfada** |

### Denetçi

| TR | EN | Alt öğeler |
|---|---|---|
| **Denetim izi** | **Audit trail** | Olay arama · Zincir bütünlüğü |
| **Kanıt paketi** | **Evidence export** | Filtre → paket → indirme |

## F.3 Global çerçeve (tüm roller)

```
┌──────────────────────────────────────────────────────────────────────┐
│ [CareOnCloud]  [Rol menüsü…]        🔍 Ara   ➕ Yeni   🔔 3   👤 TR │
│ Müşteri: ● Yetka A.Ş.  ▾            ← MSP/çok tenant'lı kullanıcıda │
└──────────────────────────────────────────────────────────────────────┘
```

- **Tenant rozeti** sol üstte, renkli nokta + ad. Tıklayınca panel açılır, **açık `Değiştir` butonu** ile geçilir (`onchange` otomatik gönderim kaldırılır — P0-06).
- **Dil** profil menüsünde; seçim `user_preferences`'a yazılır ve oturumlar arası kalır.
- **Mobil:** kök menü hamburger'a düşer, tenant rozeti başlıkta kalır (bağlam asla gizlenmez).

## F.4 TR / EN kanonik terim sözlüğü

| Kavram | TR (kanonik) | EN (kanonik) | Bugünkü hatalı kullanım |
|---|---|---|---|
| Service Domain | Hizmet Alanı | Service Domain | — |
| Service Category | Hizmet Kategorisi | Service Category | — |
| Service | **Hizmet** | Service | UI'da "Hizmet kategorisi" deniyor ❌ |
| Service Offering | **Hizmet Sunumu** | Service Offering | UI'da "Servis uzantısı" deniyor ❌ |
| Catalog Item | Katalog Öğesi | Catalog Item | — |
| Request | **Talep** | Request | Menüde "D724 Requests" ❌ |
| Incident | Olay | Incident | — |
| Ticket (miras) | **Kayıt** | Record | `BİLETLER` ❌ |
| Task | Görev | Task | — |
| Change | Değişiklik | Change | `Change Enablement` ❌ |
| Problem | Problem | Problem | — |
| Approval | Onay | Approval | — |
| Fulfillment | Gerçekleştirme | Fulfillment | — |
| Commitment / SLA | Taahhüt / SLA | Commitment / SLA | — |
| Breach | İhlal | Breach | — |
| Tenant | **Müşteri** (MSP bağlamı) / **Organizasyon** (kurum içi) | Tenant | Ham `TenantID` ❌ |
| Dashboard | **Ana sayfa** | Home | `PANO` ❌ |
| Operations Center | **Operasyon Merkezi** | Operations Center | TR yok ❌ |
| Service Portfolio | **Hizmet Portföyü** | Service Portfolio | TR yok ❌ |
| Agent Assistant | **Destek Asistanı** | **Assist** *(öneri: "Agent Assistant" belirsiz)* | TR yok ❌ |
| Audit trail | Denetim İzi | Audit trail | — |

**Durum değerleri (P0-08):**

| Makine değeri | TR | EN |
|---|---|---|
| `new` | Yeni | New |
| `in_progress` | Devam ediyor | In progress |
| `pending_approval` | Onay bekliyor | Pending approval |
| `approved` | Onaylandı | Approved |
| `rejected` | Reddedildi | Rejected |
| `completed` | Tamamlandı | Completed |
| `failed` | Başarısız | Failed |
| `breached` | İhlal edildi | Breached |

**"Bilet" / "Ticket" kararı:** Son kullanıcıya `Bilet` gösterilmemelidir. Müşteri tarafında yalnızca **Talep**; agent tarafında iş nesnesi türüne göre **Talep / Olay / Görev / Değişiklik**; ikisini kapsayan genel ad **Kayıt**. `Ticket` teknik miras olarak kodda kalır.

---

# G. Hedef ekran tasarımları

Düşük/orta ayrıntı. Örnek içerik gerçekçi Türkçedir. Her ekranda birincil görev, birincil CTA, kritik durum, boş durum ve hata durumu belirtilmiştir.

## G.1 Müşteri portalı ana sayfası

```
┌────────────────────────────────────────────────────────────────────┐
│ CareOnCloud            🔍 Ne yapmak istiyorsunuz?      🔔 2  👤 TR │
├────────────────────────────────────────────────────────────────────┤
│  Merhaba Elif,                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 🔍  Aradığınız hizmeti yazın  (örn. "yeni dizüstü")          │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  Sık kullanılanlar                                                 │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐       │
│  │ 💻 Donanım │ │ 🔑 Erişim  │ │ 🏢 Ofis    │ │ 👤 İK      │       │
│  │ talebi     │ │ talebi     │ │ hizmetleri │ │ talepleri  │       │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘       │
│                                                                    │
│  Açık talepleriniz (3)                            Tümünü gör →     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ TAL-2026-00412  Yeni dizüstü bilgisayar                      │  │
│  │ ● Devam ediyor · Sorumlu: Ahmet K. · Hedef: 6 Ağu 17:00     │  │
│  ├──────────────────────────────────────────────────────────────┤  │
│  │ TAL-2026-00398  VPN erişimi                                  │  │
│  │ ⏸ Onay bekliyor · Onaylayan: Murat D. · 2 gündür bekliyor   │  │
│  ├──────────────────────────────────────────────────────────────┤  │
│  │ TAL-2026-00377  Toplantı odası projeksiyon arızası           │  │
│  │ ⚠ Hedef süre aşıldı · Sorumlu: Tesis ekibi                  │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

- **Birincil görev:** hizmet bulmak · **Birincil CTA:** arama alanı
- **Kritik durum:** hedef süresi aşan talep sarı/kırmızı **ikon + metin** (yalnız renk değil)
- **Boş durum:** "Henüz açık talebiniz yok. İhtiyacınız olan hizmeti arayarak başlayın." + `Hizmet ara` butonu
- **Hata:** "Talepleriniz şu anda yüklenemedi." + `Yeniden dene`; arama alanı çalışmaya devam eder
- **EN uzunluk kontrolü:** `Açık talepleriniz` → `Your open requests` (+%38) — başlık alanı sabit genişlik olmamalı

## G.2 Hizmet kataloğu ve katalog öğesi

```
┌────────────────────────────────────────────────────────────────────┐
│ ← Ana sayfa   Hizmet Kataloğu                                      │
├──────────────────┬─────────────────────────────────────────────────┤
│ Hizmet alanları  │ 🔍 "dizüstü"                          12 sonuç  │
│ ▸ Bilgi Tekno…   │ ┌─────────────────────────────────────────────┐ │
│ ▸ İnsan Kayn…    │ │ 💻 Yeni dizüstü bilgisayar talebi           │ │
│ ▸ Tesis          │ │ Standart kurulumlu cihaz. Yönetici onayı    │ │
│ ▸ Saha Hizmet…   │ │ gerektirir.                                 │ │
│                  │ │ ⏱ Hedef: 5 iş günü   💰 Bütçe kodu gerekli │ │
│ Filtreler        │ │                              [ Talep aç → ] │ │
│ ☐ Onay gerekmez  │ ├─────────────────────────────────────────────┤ │
│ ☐ Aynı gün       │ │ 🔧 Dizüstü donanım arızası bildirimi        │ │
│                  │ │ ⏱ Hedef: 4 saat                            │ │
│                  │ │                              [ Talep aç → ] │ │
│                  │ └─────────────────────────────────────────────┘ │
└──────────────────┴─────────────────────────────────────────────────┘
```

**Bugüne göre değişen:** üç ardışık `<select>` yerine **arama önce, ağaç yardımcı**. Hizmet açıklaması seçim **öncesinde** görünür. SLA hedefi ve onay gerekliliği karar anında gösterilir.

- **Boş durum (arama sonuçsuz):** "'dizüstü' için hizmet bulunamadı. Aramayı genelleştirin veya kategoriye göz atın." + `Tüm kataloğu gör`
- **Yetki durumu:** yetkisiz katalog öğesi listelenmez; kullanıcı doğrudan URL ile gelirse "Bu hizmete erişim yetkiniz yok. Yöneticinizle görüşün." + iletişim bağlantısı

## G.3 Talep oluşturma adımları

```
┌────────────────────────────────────────────────────────────────────┐
│ ← Katalog     Yeni dizüstü bilgisayar talebi                       │
│  ①  Bilgiler ──────── ②  Gözden geçir ──────── ③  Gönderildi      │
├────────────────────────────────────────────────────────────────────┤
│  Seçilen hizmet                                                    │
│  Bilgi Teknolojileri › Son Kullanıcı Cihazları › Dizüstü           │
│  ⏱ Hedef çözüm: 5 iş günü   ✓ Yönetici onayı gerekir              │
│                                                                    │
│  Kullanım amacı *                                                  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                                                              │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  Cihazın kullanılacağı işi kısaca açıklayın.                      │
│                                                                    │
│  Model tercihi *          Bütçe kodu *                             │
│  [ Standart      ▾ ]      [                    ]                   │
│                           ⚠ Bütçe kodu zorunludur.                 │
│                                                                    │
│  Teslim tarihi                                                     │
│  [ 12.08.2026   📅 ]                                               │
│                                                                    │
│                          [ Vazgeç ]      [ Devam et → ]            │
└────────────────────────────────────────────────────────────────────┘
```

- **Birincil CTA:** `Devam et` (tek birincil buton)
- **Hata:** alan **altında**, ikon + metin, `aria-describedby` ile bağlı; ilk hatalı alana focus
- **Kritik durum:** onay gerektiren talepte 2. adımda "Bu talep Murat D. onayına gidecek." açıkça yazılır
- **Kayıp önleme:** doldurulmuş formdan çıkışta uyarı
- **TR/EN:** `Bütçe kodu` → `Budget code`; etiketler `label_tr`/`label_en` alanlarından gelir (P1-02)

## G.4 Müşteri talep detay / timeline

```
┌────────────────────────────────────────────────────────────────────┐
│ ← Taleplerim    TAL-2026-00412 · Yeni dizüstü bilgisayar           │
├─────────────────────────────────────────┬──────────────────────────┤
│ ● Devam ediyor                          │ Özet                     │
│                                         │ Sorumlu   Ahmet Kılıç    │
│ ⏱ Hedef çözüm: 6 Ağu 17:00 (2 gün 4 sa)│ Ekip      Son Kullanıcı  │
│ ████████████░░░░░░  %68                 │ Açılış    1 Ağu 09:12    │
│                                         │ Öncelik   Normal         │
│ Zaman çizelgesi                         │ Hizmet    Dizüstü        │
│ ┌─────────────────────────────────────┐ │                          │
│ │ ● 1 Ağu 09:12  Talep oluşturuldu    │ │ [ Bilgi ekle ]           │
│ │ ● 1 Ağu 09:13  Onaya gönderildi     │ │ [ Talebi iptal et ]      │
│ │ ● 1 Ağu 14:40  Murat D. onayladı    │ │                          │
│ │ ● 2 Ağu 08:05  Ahmet K. üstlendi    │ │                          │
│ │ ● 2 Ağu 08:30  Ahmet K.:            │ │                          │
│ │   "Cihaz siparişi verildi."         │ │                          │
│ │ ○ Bekleyen: Teslim ve kurulum       │ │                          │
│ └─────────────────────────────────────┘ │                          │
└─────────────────────────────────────────┴──────────────────────────┘
```

**Bu ekran bugün yoktur (P0-05).** Pilotun en görünür eksiği budur.

- **Kritik durum:** hedef aşıldıysa ilerleme çubuğu kırmızı **ve** "Hedef süre 4 saat aşıldı" metni
- **Boş durum:** timeline en az bir olay içerir; boş olamaz
- **Hata:** "Talep bulunamadı veya erişim yetkiniz yok." — varlık sızdırmayan tek mesaj

## G.5 Agent rol bazlı ana sayfası ("Bugün")

```
┌────────────────────────────────────────────────────────────────────┐
│ CareOnCloud  Bugün│İş listesi│Hizmetler│İyileştirme   🔍 ➕ 🔔 👤  │
│ Müşteri: ● Yetka A.Ş. ▾                                            │
├────────────────────────────────────────────────────────────────────┤
│ ⚠ SLA riski (3)                              ← EN ÜSTTE, İLK       │
│ ┌────────────────────────────────────────────────────────────────┐ │
│ │ TAL-00377  Projeksiyon arızası      Kalan: 00:42  Tesis  [Aç] │ │
│ │ TAL-00390  E-posta erişimi          Kalan: 01:15  BT     [Aç] │ │
│ │ TAL-00401  Yazıcı kurulumu          Kalan: 02:30  BT     [Aç] │ │
│ └────────────────────────────────────────────────────────────────┘ │
│                                                                    │
│ ┌──────────────────────┬──────────────────────┬──────────────────┐ │
│ │ Bana atanan (12)     │ Onayımı bekleyen (2) │ Bugünkü görev(5) │ │
│ │ TAL-00412 Dizüstü    │ TAL-00398 VPN        │ Kurulum · 14:00  │ │
│ │ TAL-00405 Yetki      │ TAL-00402 Yazılım    │ Devir · 16:00    │ │
│ │ … 10 tane daha       │                      │ … 3 tane daha    │ │
│ └──────────────────────┴──────────────────────┴──────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

- **Birincil görev:** riskli işi ilk görmek · **Birincil CTA:** `Aç`
- **Bugüne göre değişen:** OTOBO'nun boş widget'ları ve otobo.io RSS'i kaldırılır (P0-03); ekranın üst yarısı **eylem gerektiren işe** ayrılır
- **Boş durum (ideal gün):** "SLA riski taşıyan iş yok. 👍 Bana atanan 12 kaydınız var." — boş tablo değil, olumlu ifade
- **Sıfır veri:** yeni tenant'ta "Henüz kayıt yok. İlk talep geldiğinde burada görünecek."

## G.6 Agent iş listesi / kuyruk

```
┌────────────────────────────────────────────────────────────────────┐
│ İş listesi                                                         │
│ Görünüm: [ SLA riski ▾ ]  Kuyruk:[ Tümü ▾ ] Durum:[ Açık ▾ ] 🔍   │
│                                              [ Görünümü kaydet ]   │
├────────────────────────────────────────────────────────────────────┤
│ ☐ │ Kayıt      │ Konu              │ Hizmet   │ Sorumlu │ Kalan ▲ │
│ ☐ │ TAL-00377  │ Projeksiyon arı…  │ Tesis    │ —       │ ⚠ 00:42 │
│ ☐ │ TAL-00390  │ E-posta erişimi   │ BT       │ Ayşe T. │ ⚠ 01:15 │
│ ☐ │ TAL-00412  │ Yeni dizüstü      │ BT       │ Ahmet K.│  2g 4sa │
│ ☐ │ OLY-00120  │ Ağ kesintisi      │ Altyapı  │ Ekip    │  ✓ 6sa  │
├────────────────────────────────────────────────────────────────────┤
│ 2 seçili:  [ Üstlen ]  [ Ekibe ata ]  [ Öncelik değiştir ]         │
│                                     1–25 / 148   ‹ 1 2 3 … 6 ›     │
└────────────────────────────────────────────────────────────────────┘
```

- Sıralama, filtre, toplu işlem, kaydedilmiş görünüm, **sayfalama** (P1-07, P2-03)
- **Mobil:** tablo kart listesine dönüşür; **hiçbir koşulda yatay taşma yok**
- **Boş durum:** "Bu görünümde kayıt yok. Filtreleri temizleyin veya başka görünüm seçin." + `Filtreleri temizle`

## G.7 Agent talep çalışma alanı

```
┌────────────────────────────────────────────────────────────────────┐
│ ← İş listesi  TAL-2026-00412 · Yeni dizüstü bilgisayar             │
│ Müşteri: ● Yetka A.Ş.   ● Devam ediyor   ⏱ Kalan 2g 4sa           │
├──────────────────────────────────┬─────────────────────────────────┤
│ [İletişim] [Görevler 2] [İlişki] │ Talep sahibi                    │
│                                  │ Elif Yılmaz · Finans            │
│ ┌──────────────────────────────┐ │ elif.yilmaz@…  · +90 5xx        │
│ │ Elif Y. · 1 Ağu 09:12        │ │                                 │
│ │ Yeni projede kullanmak üzere │ │ Taahhütler                      │
│ │ standart dizüstü talebi.     │ │ İlk yanıt   ✓ Karşılandı        │
│ ├──────────────────────────────┤ │ Çözüm       ⏱ 6 Ağu 17:00      │
│ │ Ahmet K. · 2 Ağu 08:30       │ │                                 │
│ │ Cihaz siparişi verildi.      │ │ Görevler (2)                    │
│ └──────────────────────────────┘ │ ✓ Sipariş                       │
│                                  │ ○ Kurulum · Saha ekibi          │
│ ┌──────────────────────────────┐ │                                 │
│ │ Yanıt yazın…                 │ │ İlişkili CI                     │
│ └──────────────────────────────┘ │ + CI bağla                      │
│ [Dahili not ▾]      [ Gönder ]   │                                 │
└──────────────────────────────────┴─────────────────────────────────┘
```

**Bugüne göre değişen:** `AgentD724Request.tt` şu an tüm talepleri tek sayfaya, iletişim alanı olmadan basıyor. Burada tek kayıt + iletişim + görev + ilişki bir arada.

- **Kritik durum:** SLA kalan süre başlıkta sabit; ihlalde kırmızı rozet + metin
- **Onay eylemi (P1-06):** `Reddet` ikincil stil, **zorunlu gerekçe**, onay adımı
- **Boş durum:** "Bu kayıtta henüz iletişim yok. İlk yanıtı yazarak başlayın."
- **Çakışma hatası:** `ExpectedVersion` uyuşmazsa "Bu kayıt siz görüntülerken güncellendi. Değişiklikleriniz kaydedilmedi." + `Yenile`

## G.8 Operations Center / hizmet sağlığı

```
┌────────────────────────────────────────────────────────────────────┐
│ Operasyon Merkezi                                                  │
│ Müşteri:[ Yetka A.Ş. ▾]  Dönem:[ 1–31 Tem ▾]        [ Uygula ]    │
├────────────────────────────────────────────────────────────────────┤
│ ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐            │
│ │ Talep     │ │ Taahhüt   │ │ İhlal     │ │ SLA uyumu │            │
│ │   1.248   │ │   2.104   │ │    37     │ │  %98,2    │            │
│ │  ▲ %12    │ │           │ │  ▼ %8     │ │  ▲ 1,4 p  │            │
│ └───────────┘ └───────────┘ └───────────┘ └───────────┘            │
│                                                                    │
│ SLA uyumu — son 6 ay          │ Katalog öğesine göre talep         │
│  100%┤        ╭──╮            │ Şifre sıfırlama      ████ 312      │
│   95%┤ ╭──╮ ╭─╯  ╰─           │ Yazılım kurulumu     ███  241      │
│   90%┤─╯  ╰─╯                 │ Erişim talebi        ██   180      │
│      └────────────────        │ Donanım arızası      █    94       │
│       Şub  Nis  Haz           │                                    │
└────────────────────────────────────────────────────────────────────┘
```

- **Boş / sıfır veri (P1-03, P3-02):** "Seçilen dönemde veri yok." + `Dönemi genişlet` — **boş grafik ekseni gösterilmez**
- `%98,2` Türkçe ondalık ayracı **virgül**; EN'de `98.2%` — biçimlendirme yerelleştirmeden gelir
- `Technical key` alanı bu ekrandan kaldırılır (P1-08); rapor kaydetme "Rapor adı + görünürlük" ile sınırlanır

## G.9 Hizmet sahibi dashboard'u

```
┌────────────────────────────────────────────────────────────────────┐
│ Hizmet Sağlığı · Son Kullanıcı Cihazları                           │
├────────────────────────────────────────────────────────────────────┤
│ SLA uyumu %96,4 ▼   Ortalama çözüm 2,4 gün ▲   Yeniden açılma %4,1 │
│                                                                    │
│ Dikkat gerektiren                                                  │
│ ⚠ "Yazıcı kurulumu" talebinde çözüm süresi 3 ayda %40 arttı.      │
│   → 24 talep · ortalama 4,1 gün · hedef 2 gün      [ İncele ]     │
│ ⚠ "Dizüstü arızası" talep hacmi geçen aya göre %62 arttı.         │
│                                                    [ İncele ]      │
│                                                                    │
│ Hizmet kapsamı        Talep hacmi (12 ay)                          │
│ Sahip  Ahmet Kılıç    ▁▂▃▅▆▇▆▅▃▂▃▄                                │
│ Kritiklik  Yüksek                                                  │
│ Kapsam  842 kullanıcı                                              │
└────────────────────────────────────────────────────────────────────┘
```

- **Fark:** agent'ın operasyonel ekranından ayrı; **anomali önce, tablo sonra**
- **Boş durum:** "Bu hizmette dikkat gerektiren bir eğilim yok."

## G.10 Tenant / MSP yönetim görünümü

```
┌────────────────────────────────────────────────────────────────────┐
│ Müşteriler                                        [ + Müşteri ekle]│
├────────────────────────────────────────────────────────────────────┤
│ Müşteri        │ Kullanıcı │ Açık │ SLA   │ Sözleşme    │          │
│ ● Yetka A.Ş.   │   842     │  148 │ %98,2 │ 31.12.2026  │ [ Geç → ]│
│ ● Demir Lojis… │   310     │   61 │ %94,1 │ 30.06.2027  │ [ Geç → ]│
│ ● Kuzey Enerji │   127     │   19 │ ⚠%88,4│ 15.09.2026⚠ │ [ Geç → ]│
├────────────────────────────────────────────────────────────────────┤
│ ⚠ Kuzey Enerji sözleşmesi 42 gün içinde sona eriyor.               │
└────────────────────────────────────────────────────────────────────┘
```

**Tenant değiştirme onayı (P0-06):**

```
┌───────────────────────────────────────────┐
│ Müşteri bağlamını değiştir                │
│                                           │
│ Şu an:  ● Yetka A.Ş.                      │
│ Yeni:   ● Kuzey Enerji                    │
│                                           │
│ Bu değişiklikten sonra yalnızca Kuzey     │
│ Enerji verilerini göreceksiniz. Açık      │
│ sekmeleriniz kapanacak.                   │
│                                           │
│        [ Vazgeç ]   [ Değiştir ]          │
└───────────────────────────────────────────┘
```

- Otomatik `onchange` gönderimi **kaldırılır**; geçiş bilinçli bir eylemdir
- Aktif müşteri her sayfada rozet olarak görünür; rozet asla gizlenmez
- **Yetki durumu:** yetkisiz tenant listede görünmez

## G.11 Audit inceleme ve dışa aktarım

```
┌────────────────────────────────────────────────────────────────────┐
│ Denetim İzi                                                        │
│ Müşteri:[ Yetka ▾] Tarih:[1–31 Tem] Aktör:[ ] Nesne:[ Talep ▾]    │
│                                                       [ Filtrele ] │
├────────────────────────────────────────────────────────────────────┤
│ Zaman            │ Aktör      │ Olay              │ Nesne │ Zincir │
│ 31.07 16:42:07   │ ahmet.k    │ request.approved  │ 00412 │ ✓      │
│ 31.07 16:41:55   │ murat.d    │ approval.decided  │ 00412 │ ✓      │
│ 31.07 14:20:11   │ sistem     │ commitment.warned │ 00398 │ ✓      │
├────────────────────────────────────────────────────────────────────┤
│ Zincir bütünlüğü: 4.812 olayın tamamı doğrulandı ✓                │
│ ℹ Bu iz kurcalama tespitine yardımcı olur; WORM depolama değildir.│
│                                        [ Kanıt paketi indir ]      │
└────────────────────────────────────────────────────────────────────┘
```

- **Kritik:** alt bilgideki uyarı **zorunludur** — Master Context §7.3 "değiştirilemez audit" iddiasını yasaklıyor. Ürün dili bu sınırı ekranda söylemelidir.
- **Zincir kırıldığında:** satır kırmızı, "Zincir bütünlüğü doğrulanamadı — 3 olay" + `Ayrıntı`
- **Boş durum:** "Bu filtrelerle olay bulunamadı."

## G.12 Platform admin ana sayfası

```
┌────────────────────────────────────────────────────────────────────┐
│ Platform Yönetimi                                                  │
├────────────────────────────────────────────────────────────────────┤
│ Sistem sağlığı                                                     │
│ Web ✓   Daemon ✓   Veritabanı ✓   Arama ✓   Webhook ⚠ 3 başarısız │
│                                                                    │
│ ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐     │
│ │ Katalog          │ │ Taahhütler       │ │ Kimlik ve erişim │     │
│ │ 6 alan · 51 sunum│ │ 14 SLA · 3 takvim│ │ 842 kul. · 12 rol│     │
│ │ ⚠ 4 taslak       │ │                  │ │ OIDC ✓  SCIM ⚠   │     │
│ └──────────────────┘ └──────────────────┘ └──────────────────┘     │
│ ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐     │
│ │ Entegrasyon      │ │ Bildirimler      │ │ Denetim          │     │
│ │ 5 API · 8 webhook│ │ 22 şablon        │ │ 4.812 olay       │     │
│ │ ⚠ 3 dead-letter  │ │ ⚠ 6 çevrilmemiş  │ │                  │     │
│ └──────────────────┘ └──────────────────┘ └──────────────────┘     │
└────────────────────────────────────────────────────────────────────┘
```

- **Birincil görev:** "bir şey bozuk mu?" sorusunu 3 saniyede cevaplamak
- `⚠ 6 çevrilmemiş` kartı, P0-07'nin kalıcı çözümüdür: **çeviri eksiği ürün içinde görünür hâle gelir**
- **Boş durum:** temiz kurulumda kartlar "Henüz yapılandırılmadı" + `Kurulumu başlat`

---

# H. Tasarım sistemi başlangıç paketi

## H.1 Köprüleme stratejisi

Mevcut durum: D724 paketlerinde CSS yok; her şey CareOnCloud ESM Agent/Customer skin'ine biniyor. Tanımsız `D724KPIGrid` sınıfı bunun kanıtı (P1-04).

Üç aşamalı köprü:

1. **Katman ekle.** `packages/D724Foundation/var/httpd/htdocs/careoncloud/css/careoncloud.css` oluştur, `Loader::Agent::CommonCSS###900-CareOnCloud` ve `Loader::Customer::CommonCSS###900-CareOnCloud` ile kaydet. CareOnCloud ESM skin'inden **sonra** yüklenir, üzerine yazar. CareOnCloud ESM CSS'i değiştirilmez.
2. **Token'la izole et.** Tüm değerler CSS custom property. `Layout.pm` zaten `CustomerColorDefinitions`'ı `--col*` değişkenlerine basıyor — aynı mekanizmaya bağlan.
3. **Ayrıştır.** Yeni kabuk geldiğinde aynı token dosyası taşınır; bileşenler yeniden yazılır, token'lar sabit kalır. Token katmanı CareOnCloud ESM'dan bağımsızdır.

## H.2 Token'lar

```css
:root {
  /* Marka — canlı login ekranından ölçüldü */
  --cc-brand-primary:   #00023C;   /* lacivert (h1 rengi: rgb(0,2,60)) */
  --cc-brand-accent:    #12E3E3;   /* turkuaz (logo) */
  --cc-brand-violet:    #4B22E8;   /* mor (logo) */

  /* Semantik durum — her zaman ikon + metinle birlikte */
  --cc-success: #0F7B4F;  --cc-success-bg: #E8F5EF;
  --cc-warning: #8A5A00;  --cc-warning-bg: #FDF3E0;
  --cc-danger:  #B3261E;  --cc-danger-bg:  #FCEBEA;
  --cc-info:    #1B4F9C;  --cc-info-bg:    #EAF1FB;
  --cc-neutral: #4A5568;

  /* Yüzey */
  --cc-surface: #FFFFFF; --cc-surface-sunken: #F5F6F8;
  --cc-border: #D8DCE3;  --cc-border-strong: #9AA3B0;
  --cc-text: #1A1D26;    --cc-text-muted: #5A6274;

  /* Tipografi — 1.25 oranlı ölçek */
  --cc-font: "Quicksand", "Segoe UI", system-ui, sans-serif;
  --cc-fs-xs: 12px; --cc-fs-sm: 14px; --cc-fs-md: 16px;
  --cc-fs-lg: 20px; --cc-fs-xl: 25px; --cc-fs-2xl: 31px;
  --cc-lh-tight: 1.25; --cc-lh-base: 1.5;

  /* Spacing — 4 tabanlı */
  --cc-1:4px; --cc-2:8px; --cc-3:12px; --cc-4:16px;
  --cc-6:24px; --cc-8:32px; --cc-12:48px;

  /* Radius / elevation */
  --cc-r-sm:4px; --cc-r-md:8px; --cc-r-lg:12px; --cc-r-full:999px;
  --cc-e-1: 0 1px 2px rgba(26,29,38,.08);
  --cc-e-2: 0 4px 12px rgba(26,29,38,.10);

  /* Etkileşim */
  --cc-focus: 0 0 0 3px rgba(75,34,232,.45);
  --cc-target-min: 44px;   /* WCAG 2.2 AA — 2.5.8 */
}
```

**Kontrast doğrulaması (WCAG 2.2 AA, ≥4.5:1):**

| Kombinasyon | Oran | Sonuç |
|---|---|---|
| `--cc-text` #1A1D26 / beyaz | 16,1:1 | ✓ |
| `--cc-text-muted` #5A6274 / beyaz | 6,4:1 | ✓ |
| beyaz / `--cc-brand-primary` #00023C | 18,9:1 | ✓ |
| `--cc-danger` #B3261E / `--cc-danger-bg` | 5,9:1 | ✓ |
| `--cc-warning` #8A5A00 / `--cc-warning-bg` | 5,6:1 | ✓ |
| **`--cc-brand-accent` #12E3E3 / beyaz** | **1,6:1** | ✗ **metin/ikon için kullanılamaz** — yalnız dekoratif |

Son satır bağlayıcıdır: turkuaz marka rengi logoda kalır, durum veya bağlantı rengi olarak kullanılmaz.

## H.3 Breakpoint ve grid

| Ad | Genişlik | Davranış |
|---|---|---|
| `sm` | < 640 | Tek kolon; tablo → kart; menü hamburger; tenant rozeti **kalır** |
| `md` | 640–1024 | 2 kolon; yan panel altta |
| `lg` | 1024–1440 | 12 kolonluk grid; agent 8+4 |
| `xl` | > 1440 | İçerik `max-width: 1440px` |

**Kural:** geniş içerik (tablo, grafik, kod) **kendi `overflow-x:auto` kabında** kaydırılır; `body` asla yatay kaymaz.

## H.4 Bileşen listesi ve kullanım yeri

| Bileşen | Varyantlar | Erişilebilirlik kuralı | Kullanıldığı ekran |
|---|---|---|---|
| Button | primary / secondary / danger / ghost | min 44×44; `:focus-visible` görünür halka; devre dışı halde de kontrast | Tümü |
| Input / Textarea | normal / hata / devre dışı | `<label for>` **zorunlu**; `placeholder` etiket yerine geçmez; hata `aria-describedby` | G.3, G.7 |
| Select | tek / çoklu / aranabilir | **`onchange` ile form gönderimi yasak** (WCAG 3.2.2) | G.2, G.8, G.10 |
| Date / DateTime | — | Klavyeyle girilebilir; TR formatı `gg.aa.yyyy` | G.3, G.8 |
| Status badge | 8 durum | **İkon + metin**, yalnız renk değil (WCAG 1.4.1) | G.1, G.4, G.6 |
| SLA indicator | normal / uyarı / ihlal | Kalan süre metni + ikon; ekran okuyucuya tam metin | G.5, G.6, G.7 |
| Tenant badge | tek / çok tenant | Her sayfada; `aria-live` ile değişim duyurusu | Global |
| Table | sıralanabilir / seçilebilir | `<th scope>`; sıralama `aria-sort`; mobilde karta dönüşür | G.6, G.11 |
| Pagination | — | Klavyeyle gezilebilir; "1–25 / 148" metni | G.6, G.11 |
| Card / Metric tile | nötr / uyarı | Trend yalnız okla değil, metinle de (`▲ %12`) | G.1, G.8 |
| Timeline | — | `<ol>`; her olayda mutlak zaman damgası | G.4, G.7 |
| Empty state | ilk kullanım / filtre boş / yetki yok | Her zaman bir sonraki eylemi önerir | **Tüm listeler** |
| Error state | alan / form / sayfa | Hata ne olduğunu ve ne yapılacağını söyler | Tümü |
| Skeleton | satır / kart | `aria-busy="true"` | Tümü |
| Modal / Drawer | onay / detay | Focus tuzağı **bilinçli**; `Esc` kapatır; açan öğeye focus döner | G.10 |
| Toast | başarı / hata | `role="status"`; en az 5 sn; hata otomatik kapanmaz | Tümü |

## H.5 Erişilebilirlik kabul kuralları (WCAG 2.2 AA)

1. `<html lang>` aktif dile göre dolu (**3.1.1 A — bugün ihlal**)
2. Hiçbir `<select>` değişimde sayfa gezinmesi tetiklemez (**3.2.2 A — bugün ihlal**)
3. Bilgi yalnızca renkle aktarılmaz (**1.4.1 A**)
4. Metin kontrastı ≥4.5:1, UI bileşeni ≥3:1 (**1.4.3 / 1.4.11 AA**)
5. Tüm etkileşimli öğe klavyeyle erişilebilir, focus **görünür** (**2.1.1 / 2.4.7**)
6. Focus, yapışkan başlık altında gizlenmez (**2.4.11 AA — 2.2 yenisi**)
7. Tıklama hedefi ≥24×24 CSS px, hedef ≥44 (**2.5.8 AA — 2.2 yenisi**)
8. Sürükleme gerektiren her işlemin tek tıkla alternatifi var (**2.5.7 AA — 2.2 yenisi**)
9. Aynı akıştaki bilgi tekrar sorulmaz (**3.3.7 AA — 2.2 yenisi**)
10. AccessKey'ler benzersiz (**bugün ihlal — P1-05**)

---

# I. Aşamalı geliştirme yol haritası

## I.0 Uygulama sınıfı ayrımı

**Düşük muhakeme / düşük token ile uygulanabilir** — kabul ölçütü mekanik:

- TR/EN metin kataloğu doldurma (`tr_*.pm` eksik anahtarlar)
- CSS token dosyası ve `Loader` kaydı
- ALL-CAPS TR terim düzeltmeleri (`tr.pm` 3 satır)
- AccessKey benzersizlik kontrolü ve düzeltmesi
- `Layout.pm:4221` fallback değişimi
- Marka sözleşme testine string taraması ekleme
- `<html lang>` yazımı
- Rota / marka tarama testleri, screenshot regression
- `axe-core` otomasyonu CI'ya bağlama
- Boş durum metinlerinin şablonlara eklenmesi

**Yüksek muhakeme / kıdemli model veya insan kararı gerekli:**

- Bilgi mimarisi ve rol bazlı menü ağacı
- Katalog terminolojisi kararı (K-2) ve migration
- Request ↔ Ticket birleştirme kararı (K-1)
- Agent ekran yoğunluğu dengesi
- Tenant bağlam modeli ve güvenlik sınırı
- Tasarım sistemi mimarisi ve CareOnCloud ESM'dan ayrışma sırası
- CareOnCloud API sözleşmelerinin sınırı
- Kritik yolculukların yeniden tasarımı

## I.1 Dilimler

### `P0 / Pilot kapıları` — 0–4 hafta · Efor **M**

| Alan | İçerik |
|---|---|
| Kullanıcı sonucu | Müşteri ve agent, başka bir ürünün markasını görmeden, kendi dilinde giriş yapar |
| Ekranlar | Her iki login, global başlık, dil/saat dilimi tercihi |
| Tasarım işi | Login düzeni, dil seçici, TR/EN metinler |
| Frontend işi | `Layout.pm:4221`, `<html lang>`, `LoginBG`, `tr.pm` düzeltmeleri, `Framework.xml` otobo.io temizliği |
| API/domain | **Yok** |
| Veri/permission | Yok |
| Test | Marka string taraması (yeni), TR/EN login kabulü, `axe-core` login |
| Telemetri | Login başarı oranı, dil dağılımı |
| Geri dönüş | Salt config/şablon; commit geri alınır |
| Bağımlılık | Cutover (P0-02) ayrı ve bloklayıcı |

### `P0 / Cutover` — 2–5 hafta · Efor **M** *(paralel, ayrı risk)*

Aday portta `careoncloud-v0.1.0`, `/careoncloud/` kabulü, rollback provası, ancak sonra kesim. Master Context §8.3'teki 12 adımlı sıra bağlayıcıdır. **Bu iş UX değil operasyon işidir; ama UX'in en görünür P0'ını (adres çubuğu) yalnızca bu çözer.**

### `P1 / Yeni müşteri portalı` — 4–12 hafta · Efor **L**

| Alan | İçerik |
|---|---|
| Kullanıcı sonucu | Müşteri hizmeti arar, talep açar **ve talebini takip eder** |
| Ekranlar | G.1, G.2, G.3, G.4 |
| Tasarım işi | Katalog arama düzeni, form adımları, timeline |
| Frontend işi | Yeni `CustomerD724Requests` liste + detay modülü; katalog arama; token'lı CSS |
| API/domain | **Request read/list sözleşmesi** — CareOnCloud domain üzerinden, CareOnCloud ESM tablosuna doğrudan erişim yok |
| Veri/permission | Müşteri yalnız kendi + yetkili organizasyon taleplerini görür — negatif test şart |
| Test | Uçtan uca TR ve EN yolculuk; tenant sızıntı negatif testi; `axe-core` |
| Telemetri | Talep açma tamamlanma oranı, "durumum ne" destek çağrısı sayısı |
| Geri dönüş | Yeni modüller `Valid=0` ile kapatılır; eski akış çalışır |
| Bağımlılık | K-2 (katalog terminolojisi) |

### `P1 / Yeni agent çalışma kabuğu` — 8–18 hafta · Efor **L**

| Alan | İçerik |
|---|---|
| Kullanıcı sonucu | Agent riskli işi ilk görür, tek ekranda çözer |
| Ekranlar | G.5, G.6, G.7 |
| Tasarım işi | "Bugün" düzeni, iş listesi ergonomisi, çalışma alanı |
| Frontend işi | Filtre/sıralama/sayfalama/toplu işlem; tenant rozeti; onay akışı |
| API/domain | Request query sözleşmesi (filtre, sıralama, sayfalama); commitment okuma |
| Veri/permission | TenantGuard her sorguda; kaydedilmiş görünüm tenant'a bağlı |
| Test | SLA sıralama doğruluğu; toplu işlem yetki testi; klavye gezinme |
| Telemetri | İlk yanıt süresi, SLA ihlal oranı, ekranlar arası geçiş sayısı |
| Geri dönüş | Eski `AgentD724Request` korunur, menüden gizlenir |
| Bağımlılık | K-1 (request/ticket kararı) — **bloklayıcı** |

### `P2 / Admin ve MSP deneyimi` — 12–24 hafta · Efor **L**

Ekranlar: G.10, G.11, G.12 + kimlik/entegrasyon yönetimi. Bugün **sıfırdan** başlıyor. Denetçi ekranı (G.11) regüle müşteri için satış kapısı olduğundan bu dilimin başına alınmalıdır.

### `P2 / Tasarım sistemi yaygınlaştırma` — 16–28 hafta · Efor **M**

Token + bileşenlerin tüm D724 ekranlarına uygulanması; CareOnCloud ESM skin bağımlılığının azaltılması; screenshot regression.

### `P3 / CareOnCloud ESM UI bağımsızlığı` — 24+ hafta · Efor **XL**

Master Context §4.2 ayrışma sırası korunur. **Ticket ve e-posta çekirdeği en sonda kalır.**

## I.2 Ardışıklık

```
P0 Pilot kapıları ──┬─→ P1 Müşteri portalı ──┐
                    │        ↑ K-2            ├─→ P2 Tasarım sistemi ─→ P3
P0 Cutover ─────────┘   P1 Agent kabuğu ──────┤
                             ↑ K-1            │
                        P2 Admin/MSP ─────────┘
```

Bloklayıcılar: **K-1** agent kabuğunu, **K-2** müşteri portalını bloklar. İkisi de ürün sahibi kararıdır ve I.1'in ilk dilimi çalışırken verilmelidir.

---

# J. İlk iki sprint backlog'u

## Sprint 1 — "Marka ve dil kapısı"

### J1. Müşteri giriş ekranından CareOnCloud ESM markasını kaldır

- **Hikâye:** Müşteri olarak giriş ekranında yalnızca CareOnCloud markasını görmek istiyorum ki doğru ürüne girdiğimden emin olayım.
- **Kapsam:** `Layout.pm:4221` fallback; `CustomerLogin::Settings.LoginText` varsayılanı; `LoginBG.jpg` değişimi; `careon-signet.png` / `careoncloud-signet.png` ad tutarsızlığının giderilmesi.
- **Kapsam dışı:** Login düzeninin yeniden tasarımı.
- **Tasarım kabulü:** Slogan CareOnCloud konumlandırmasını yansıtır; arka plan görseli marka ile uyumlu.
- **Teknik kabulü:** `customer.pl` HTML çıktısında `CareOnCloud ESM` **geçmez**; fallback çevrilebilir.
- **TR/EN kabulü:** TR oturumda "Hizmet Bulutta, Kontrol Sizde." / EN'de karşılığı; karışım yok.
- **WCAG kabulü:** Başlık kontrastı ≥4.5:1; `<h1>` tek ve anlamlı.
- **Kanıt:** `curl -s .../customer.pl | grep -i careoncloud` → boş; iki dilde ekran görüntüsü.
- **Bağımlılık:** Yok. **Geri dönüş:** Tek commit revert.

### J2. Marka sözleşme testine render metni taraması ekle

- **Hikâye:** Ekip olarak, kullanıcıya görünen CareOnCloud ESM metninin CI'da yakalanmasını istiyorum ki J1 tekrar bozulmasın.
- **Kapsam:** `Test-CareOnCloudBrand.ps1` içine `Kernel/Output/HTML/**/*.tt`, `Kernel/Output/HTML/Layout.pm`, `Kernel/Config/Files/XML/Framework.xml` ve `packages/**/*.tt` için yasaklı string taraması. Allow-list: `README`, `NOTICE`, `UPSTREAM.md`, `LICENSE`, telif başlıkları, `Kernel/Language/*.pm`.
- **Kapsam dışı:** Runtime HTTP taraması (ayrı kart).
- **Teknik kabulü:** `Layout.pm:4221` eski hâline döndürülürse test **kırmızı** olur — bu doğrulanarak gösterilir.
- **Kanıt:** Kasıtlı regresyon commit'i ile kırmızı, düzeltmeyle yeşil çıktı.
- **Bağımlılık:** J1. **Geri dönüş:** Test dosyası revert.

### J3. `<html lang>` doldur

- **Hikâye:** Ekran okuyucu kullanıcısı olarak sayfanın dilinin doğru algılanmasını istiyorum.
- **Kapsam:** Agent, müşteri ve public layout'larda aktif kullanıcı diline göre `lang`.
- **WCAG kabulü:** **3.1.1 (A)** karşılanır; `axe-core` `html-has-lang` ve `valid-lang` geçer.
- **Kanıt:** TR ve EN oturumda `axe-core` raporu; DOM'da `lang` değeri.
- **Bağımlılık:** Yok. **Geri dönüş:** Tek commit revert.

### J4. Çekirdek Türkçe menü terimlerini düzelt

- **Kapsam:** `tr.pm:2967` `Dashboard`→`Ana sayfa`; `tr.pm:156` `Calendar`→`Takvim`; `tr.pm:3069` `Tickets`→`Kayıtlar`.
- **Kapsam dışı:** Menü yapısının değişmesi (F.2, P2-01).
- **TR/EN kabulü:** Menüde ALL-CAPS Türkçe kalmaz; EN etkilenmez.
- **Kanıt:** TR oturum menü ekran görüntüsü; `grep` ile ALL-CAPS taraması.
- **Bağımlılık:** Yok. **Geri dönüş:** Üç satır revert.

### J5. Agent dashboard'undan otobo.io widget'larını kaldır

- **Kapsam:** `Framework.xml:8726, 8727, 8763, 9267`.
- **Teknik kabulü:** Dashboard yüklenirken `otobo.io`'ya **hiç ağ isteği** gitmez.
- **Kanıt:** Tarayıcı ağ kaydı; HTML'de `otobo.io` yok.
- **Bağımlılık:** J2 (test kapsar). **Geri dönüş:** XML revert.

### J6. Menü adlarını Türkçeleştir ve AccessKey çakışmasını gider

- **Kapsam:** `Agent Assistant`→`Destek Asistanı`, `Operations Center`→`Operasyon Merkezi`, `Service Portfolio`→`Hizmet Portföyü`, `Change Enablement`→`Değişiklik Yönetimi`, `Problem Management`→`Problem Yönetimi`, `D724 Requests`→**EN'de de** `Requests` / TR `Talepler`. `D724Problem` AccessKey `p`→`b`.
- **Teknik kabulü:** Kaynakta AccessKey tekrarı yok; CI kontrolü eklenir.
- **TR/EN kabulü:** TR menüde İngilizce ad yok; **hiçbir menüde `D724` geçmez**.
- **Kanıt:** İki dilde menü ekran görüntüsü; AccessKey benzersizlik testi.
- **Bağımlılık:** F.4 sözlüğü onayı. **Geri dönüş:** XML + `tr_*.pm` revert.

### J6b. Demo verisini sentetikleştir *(P0-11 — sprint 1'in en yüksek öncelikli kartı)*

- **Hikâye:** Ürün sahibi olarak demo ortamında hiçbir gerçek kurumun adının geçmemesini istiyorum ki demo sırasında hukuki ve itibari risk doğmasın.
- **Kapsam:** ~40 `demo-*` tenant kaydı ve bunlara bağlı talep/commitment/audit verisi. Sentetik set üret: `Yetka A.Ş.`, `Demir Lojistik`, `Kuzey Enerji`, `Marmara Tekstil`, `Ege Gıda` vb. Slug'lar Türkçe karakter bozmadan üretilir (`yetka-as`, `kuzey-enerji`).
- **Kapsam dışı:** Demo senaryolarının içerik olarak yeniden yazılması.
- **Teknik kabulü:** Tenant listesinde, audit kayıtlarında, katalog ve rapor çıktılarında hiçbir gerçek kurum adı geçmez. Yasaklı isim listesi CI taramasına eklenir.
- **TR/EN kabulü:** Sentetik adlar iki dilde de doğal görünür.
- **Kanıt:** Tenant seçicisi ekran görüntüsü; isim listesi taraması yeşil.
- **Bağımlılık:** K-9 kararı (eğer izin alınmışsa kapsam daralır). **Geri dönüş:** Demo DB snapshot'ından geri yükleme.
- **Not:** Bu iş bir UX iyileştirmesi değildir; **demo yapılmadan önce** kapatılması gereken bir kapıdır.

### J6c. Talep sahibini isimle göster *(P0-12)*

- **Kapsam:** `AgentD724Request.tt` — `Requester: customer:<64 hex>` yerine ad, soyad ve organizasyon.
- **Teknik kabulü:** Hash kullanıcıya görünmez; çözümleme yetki sınırına saygı duyar.
- **Kanıt:** Ekran görüntüsü; yetkisiz tenant'ta kişi bilgisi sızmadığı testi.
- **Bağımlılık:** Customer directory lookup. **Geri dönüş:** Şablon revert.

## Sprint 2 — "Müşteri talebini görebilsin"

### J7. Durum değerlerini çevrilebilir yap

- **Kapsam:** F.4 durum tablosundaki 8 değer; `AgentD724Request.tt`, `CustomerD724Request.tt` içinde `Translate(Data.Status)`; `AgentD724Request.tt` içindeki ` — assigned: ` metni.
- **Teknik kabulü:** Şablonlarda ham makine değeri basılmaz.
- **TR/EN kabulü:** Aynı kayıt TR'de "Devam ediyor", EN'de "In progress".
- **Kanıt:** İki dilde ekran görüntüsü; çevrilmemiş string taraması (J2 testine eklenir).
- **Bağımlılık:** J2. **Geri dönüş:** Şablon revert.

### J8. Tenant seçimini adla ve bilinçli yap

- **Hikâye:** MSP yöneticisi olarak müşteri bağlamını **adıyla** ve kazara değil bilerek değiştirmek istiyorum.
- **Kapsam:** `AgentD724Request.tt:6-7` — `onchange` kaldırılır, açık `Uygula` butonu; seçenekler tenant **adıyla**; global tenant rozeti.
- **Kapsam dışı:** G.10 MSP panosu.
- **Tasarım kabulü:** Aktif müşteri her sayfada görünür; değişim onay ister.
- **Teknik kabulü:** Tenant listesi ad alanı `TenantDirectory`'den; yetkisiz tenant listelenmez.
- **WCAG kabulü:** **3.2.2 (A)** karşılanır; değişim `aria-live` ile duyurulur.
- **Kanıt:** Yetkisiz tenant negatif testi; klavyeyle geçiş kaydı.
- **Bağımlılık:** TenantDirectory ad alanı. **Geri dönüş:** Şablon revert.

### J9. "Taleplerim" listesi

- **Hikâye:** Müşteri olarak açtığım talepleri tek listede görmek istiyorum ki durumunu sormak için aramayayım.
- **Kapsam:** Yeni `CustomerD724Requests` modülü + şablonu; müşteri portalı menüsüne `Taleplerim`; durum, sorumlu, hedef süre, açılış tarihi; sayfalama.
- **Kapsam dışı:** Timeline detayı (J10).
- **Tasarım kabulü:** G.1'deki liste düzeni; SLA durumu ikon + metin.
- **Teknik kabulü:** Yalnız kendi/yetkili organizasyon talepleri; CareOnCloud domain sözleşmesi üzerinden — **CareOnCloud ESM tablosuna doğrudan sorgu yok**.
- **TR/EN kabulü:** Tüm metinler iki dilde; tarih TR `gg.aa.yyyy`, EN `dd Mmm yyyy`.
- **WCAG kabulü:** Tablo `<th scope>`; mobilde yatay taşma yok; boş durum metni var.
- **Kanıt:** Uçtan uca test: talep aç → listede gör; başka müşterinin talebi **görünmez** (negatif test).
- **Bağımlılık:** Request list API. **Geri dönüş:** Modül `Valid=0`.

### J10. Talep detay ve zaman çizelgesi

- **Kapsam:** G.4 ekranı; olay listesi, taahhüt durumu, sorumlu, `Bilgi ekle`.
- **Kapsam dışı:** Ek dosya yükleme, talep iptali.
- **Tasarım kabulü:** Timeline `<ol>`; her olayda mutlak zaman; SLA ilerlemesi ikon + metin.
- **Teknik kabulü:** Erişim yoksa varlık sızdırmayan tek mesaj.
- **Kanıt:** İki dilde ekran görüntüsü; yetkisiz erişim testi.
- **Bağımlılık:** J9, request event API. **Geri dönüş:** Modül `Valid=0`.

### J10b. Admin formlarını etiketle *(P0-15)*

- **Hikâye:** Platform yöneticisi olarak her alanın ne olduğunu ve biriminin ne olduğunu ekrandan görmek istiyorum.
- **Kapsam:** `AdminD724Catalog.tt` (9 alan) ve `AdminD724Commitment.tt` (11 alan) — her alana `<label for>`, sayısal alanlara birim (`saniye`, `%`), `CalendarID` ve `WarningPercent` için yardım metni. `Status` seçicisindeki yinelenen seçenek düzeltilir (P1-12). Tenant seçicisinden `onchange` kaldırılır (P0-06 ikinci konum).
- **Kapsam dışı:** SLA JSON editörü (J-sonraki, P1-10).
- **WCAG kabulü:** `axe-core` `label`, `select-name`, `form-field-multiple-labels` kuralları geçer.
- **TR/EN kabulü:** Etiketler, birimler ve `active`/`inactive` durumları iki dilde.
- **Kanıt:** `axe-core` raporu; iki ekranın TR ve EN görüntüsü.
- **Bağımlılık:** J8 (tenant deseni). **Geri dönüş:** Şablon revert.

### J11. D724 CSS temeli ve KPI ızgarası

- **Kapsam:** `careoncloud.css` (H.2 token'ları), `Loader::Agent::CommonCSS###900-CareOnCloud` + Customer eşdeğeri; `D724KPIGrid` / `D724KPI` tanımları.
- **Kapsam dışı:** Tüm ekranların yeniden stillenmesi.
- **Tasarım kabulü:** KPI'lar 1280'de 4'lü, 768'de 2'li, 375'te tek kolon.
- **Teknik kabulü:** CareOnCloud ESM skin dosyaları **değişmez**; katman üstte.
- **WCAG kabulü:** Kontrast tablosu (H.2) doğrulanır; `:focus-visible` görünür.
- **Kanıt:** Üç genişlikte screenshot; `axe-core` kontrast geçer.
- **Bağımlılık:** Yok. **Geri dönüş:** Loader kaydı `Valid=0` → eski görünüm.

### J12. Boş durum metinleri

- **Kapsam:** 10 D724 şablonunun tamamına boş durum bloğu + önerilen eylem.
- **Teknik kabulü:** Veri yokken hiçbir ekranda boş beyaz alan kalmaz.
- **TR/EN kabulü:** Metinler iki dilde.
- **Kanıt:** Temiz tenant'ta 10 ekranın screenshot'ı.
- **Bağımlılık:** J11. **Geri dönüş:** Şablon revert.

---

# K. Karar günlüğü

| ID | Karar | Seçenekler | Önerim | Gerekçe | Maliyet | Geri dönüş etkisi |
|---|---|---|---|---|---|---|
| **K-1** | D724 Request ile CareOnCloud ESM Ticket ilişkisi | (a) Ayrı kalsın (bugünkü) · (b) Request ticket üretsin, ticket iş nesnesi olsun · (c) Request tek iş nesnesi, ticket geri plana çekilsin | **(b) kısa vade, (c) hedef** | Kodda hiç bağ yok; agent iki yerde çalışıyor. (b) mevcut olgun ticket yeteneklerini korur, (c) Master Context §4.2 ayrışma hedefiyle uyumlu ama ticket çekirdeğine dokunmayı gerektirir — o en sona bırakılmalı. | (b) M, (c) XL | (b) adapter katmanında geri alınır; (c) veri modeli değişimi, zor |
| **K-2** | Katalog terminolojisi | (a) Bugünkü ("Hizmet kategorisi" = Service, "Servis uzantısı" = Offering) · (b) Master Context kanonik modeli · (c) Basitleştirilmiş 3 düzey | **(b)** | (a) ekiple kullanıcıyı farklı kavramlara mahkûm ediyor ve Master Context §3.2 bunu pilot öncesi çözülmesi gereken risk olarak işaretliyor. (c) 6 alan / 51 sunum verisini kaybettirir. | M — UI metni + migration | Şema sürümleme varsa geri alınabilir; yoksa zor. **Sürümleme K-2'den önce gelmeli.** |
| **K-3** | "Agent Assistant" ürün adı | (a) `Agent Assistant` / `Destek Asistanı` · (b) `Assist` / `Asistan` · (c) Kaldır, sonuçları arama içine göm | **(b)** | "Agent Assistant" İngilizcede belirsiz (agent'a mı yardım ediyor, agent mı?). Modül Master Context §5'te "AI ürünü değildir, prototip" olarak işaretli — iddialı ad riskli. | S | Yalnız metin |
| **K-4** | Son kullanıcıda "Bilet" terimi | (a) Koru · (b) `Kayıt` · (c) Bağlama göre `Talep`/`Olay`/`Görev` | **(c), genel ad (b)** | "Bilet" CareOnCloud ESM mirası ve ESM konumlandırmasına aykırı; ürün İK ve tesis taleplerini de yönetiyor. | S — sözlük | Yalnız metin |
| **K-5** | Cutover zamanlaması | (a) UX işlerinden önce · (b) sonra · (c) paralel | **(c)** | `/careoncloud/` en görünür P0 ama cutover operasyon riski taşır ve UX işlerini bloklamamalı. Kaynak zaten doğru; UX işleri cutover'dan bağımsız ilerleyebilir. | M | Master Context §8.3 rollback sırası |
| **K-6** | Yeni frontend teknolojisi | (a) TT şablonlarını modernize et · (b) Yeni SPA kabuğu, kademeli · (c) Ekran ekran strangler | **(a) + (c)** | 10 şablon küçük; token katmanı ile (a) haftalar içinde görünür değer verir. Yeni portal ekranları (c) ile ayrı gelir. (b) tek başına 6+ ay boyunca hiçbir şey teslim etmez ve Master Context "her şeyi yeniden yazma" kuralına aykırı. | (a) M, (c) L | (a) tamamen geri alınabilir (Loader `Valid=0`); (c) modül bazlı |
| **K-7** | Cloudflare Insights beacon | (a) Koru · (b) Kaldır · (c) Rıza sonrası yükle | **(b) pilot için** | Login sayfasında rızasız üçüncü taraf istek; regüle müşteri ve KVKK sorusu. Ölçüm ihtiyacı self-hosted çözülebilir. | S | Altyapı ayarı |
| **K-9** | Canlıdaki gerçek şirket adlı demo tenant'ları | (a) Kalsın · (b) Sil, güncel sentetik seed'i çalıştır · (c) Yerinde anonimleştir | **(b)** | Kod tarafı zaten çözülmüş: güncel seed script'leri sentetik (`Marmara Bank Demo`, `Anadolu Moda Demo`, `Perakende360 Demo`). Yapılacak iş yalnızca eski canlı veriyi temizleyip güncel seed'i çalıştırmak. (c) bağlı talep/audit geçmişini tutarsız bırakır. | S | Demo DB snapshot ile geri alınır. **Karar sahibine tek soru: bu tenant'lara bağlı gösterilmek istenen bir demo senaryosu var mı?** Yoksa karar teknik olarak nettir. |
| **K-8** | `D724` namespace'inin ömrü | (a) Kalsın · (b) Kullanıcıya görünen her yerden çıksın, kodda kalsın · (c) Tamamen yeniden adlandır | **(b)** | Master Context §1.1 zaten bunu söylüyor. (c) 18 paket, 17 XML, DB şeması — pilot öncesi gereksiz risk. | S (b) / XL (c) | (b) yalnız metin |

---

# Ek: Kalite eşiği kontrolü

| Talimat §7 koşulu | Durum |
|---|---|
| Tek ekran / yalnız görsel stil incelenmemiş | ✓ 6 canlı yüzey + 10 şablon + 17 XML + 3 çekirdek dosya |
| Müşteri / agent / admin deneyimleri ayrılmış | ✓ D.1, F.2, G |
| TR/EN somut kabul kriterlerine bağlanmış | ✓ E, F.4, J (her kartta TR/EN kabulü) |
| `/careoncloud/` ve marka kalıntıları ele alınmış | ✓ A.0, P0-01…04, J1, J2, J5 |
| Tenant/MSP bağlamı ve yetki görünürlüğü değerlendirilmiş | ✓ C-14, P0-06, G.10, J8 |
| WCAG 2.2 AA, klavye, responsive incelenmiş | ✓ C-11/12, H.5, doğrulanmış 3 ihlal |
| Öneriler kaynak/teknik yapıyla ilişkilendirilmiş | ✓ Her bulguda dosya:satır |
| Bulgular P0–P3 ve atomik kartlara dönüşmüş | ✓ E, J (12 kart) |
| Tasarım / frontend / API-domain ayrıştırılmış | ✓ I.1 her dilimde ayrı satır |
| Görülmeyen alanlar görülmüş gibi raporlanmamış | ✓ B.4 gözlenen 3 agent ekranını, B.5 gözlenmeyen 6 alanı ayrı ayrı listeler; canlının eski build olduğu her yerde belirtilmiştir |

---

# Ek 2: Gözlem sonrası revizyon notu

Bu raporun ilk hâli yalnızca kaynak kod ve kimlik doğrulaması gerektirmeyen yüzeylerle yazıldı. Kullanıcı `demo.agent` oturumunu açtıktan sonra üç agent ekranı doğrudan gözlendi ve rapor güncellendi.

**Kaynaktan öngörülüp çalışma zamanında doğrulanan bulgular:** `D724KPIGrid` ızgara olmuyor · `onchange="this.form.submit()"` tenant değiştiriyor · ham makine durum değerleri ekranda · boş `lang` · `h1` içinde `D724` · ISO tarih biçimi · boş durum metinlerinin yokluğu.

**Yalnızca gözlemle ortaya çıkan, kaynaktan görülemeyen bulgular:** `P0-11` gerçek şirket adları · `P0-12` talep sahibinin hash olarak görünmesi · `P0-13` `YENI`/`YENİ` büyük harf bozulması · `P0-14` kalıcı İngilizce saat dilimi banner'ı · `P1-11` katalogda kalmış test artefaktları · 961 px'te menünün hamburger'a düşmesi · tenant slug'larında Türkçe karakter bozulması (`demo-i-s-bankasi-almanya`).

**Üçüncü tur — admin ekranları.** `demo.agent` hesabının admin yetkisi taşıdığı anlaşılınca `AdminD724Catalog` ve `AdminD724Commitment` de gözlendi. Buradan `P0-15` (admin formlarında etiket yokluğu), `P1-10` (SLA politikasının ham JSON olması), `P1-12` (yinelenen durum seçeneği) çıktı ve **skor kartındaki "Form kullanılabilirliği" puanı 2'den 1'e düşürüldü** — ilk değerlendirme yalnızca müşteri/agent şablonlarına bakmıştı ve admin tarafını olduğundan iyi göstermişti.

**Müşteri portalı** müşteri hesabı bulunmadığı için çalışır hâlde görülemedi; B.7'de yalnızca kaynak koddan, `VERIFIED_IN_SOURCE` etiketiyle değerlendirilmiştir.

**Dördüncü tur — tercihler ekranı ve bir düzeltme.** `AgentPreferences` gözlendi; `P0-16` (`translate.otobo.org` bağlantısı), `P0-17` (`Türkçe … (in process)` ve 50 dilin listelenmesi), `P0-18` (varsayılan saat diliminin UTC olması — `P0-14`'ün kök nedeni) ve `P2-07` (Gravatar) çıktı.

**Düzeltme — `P0-11`:** Bu raporun önceki hâli gerçek şirket adlarının kök nedenini *"demo verisi gerçek isimlerden türetilmiş"* diye yazıyordu. Bu yanlıştı. Kaynak tarandığında bu adların **güncel kod tabanında hiç bulunmadığı** görüldü; `Seed-CareOnCloudShowcase.pl` (`Marmara Bank Demo`, `Anadolu Moda Demo`, `Perakende360 Demo`), `Seed-D724Demo.pl` (`D724 Demo Company`) ve `Seed-CareOnCloudManagedServicesCatalog.pl` tamamen sentetik ad kullanıyor; showcase script'inin başlığında *"No named organization is a customer reference"* notu var. Yani ekip bunu kodda zaten çözmüş; canlıdaki kayıtlar **eski DB verisidir**. Bulgunun önemi `P0` olarak kalır (demo öncesi mutlaka temizlenmeli) ama çözümü kod değişikliği değil, **veri temizliği + CI'da isim taraması**tır. `K-9` kararı buna göre daraltılmalıdır.

**Mevcut demo müşteri hesapları — canlıda doğrulandı.** `AdminCustomerUser` üzerinden dört hesabın da mevcut ve `valid` olduğu görüldü:

| Login | Ad | Tenant | Oluşturma |
|---|---|---|---|
| `demo.customer` | D724 Demo Customer | `d724-demo` | 25.07.2026 09:07 |
| `bank.demo` | Deniz Bankacılık Demo | `showcase-bank` | 25.07.2026 07:43 |
| `moda.demo` | Ece Moda Demo | `showcase-fashion` | 25.07.2026 07:36 |
| `retail.demo` | Mert Perakende Demo | `showcase-retail` | 25.07.2026 07:36 |

Parolalar seed sırasında `CAREONCLOUD_DEMO_PASSWORD` ortam değişkeninden atanmıştır (script en az 12 karakter dayatır). Müşteri portalı gözlemi için **yeni hesap oluşturmaya gerek yoktur.**

Ek olarak bu üç showcase tenant'ı (`showcase-bank`, `showcase-fashion`, `showcase-retail`) canlıda **gerçek şirket adlı ~40 tenant'la yan yana** duruyor. Yani sentetik seed çalıştırılmış ama eski veri temizlenmemiştir — `P0-11` düzeltmesinin canlıdaki kanıtı budur.

Aday imaj (`careoncloud-v0.1.0`) ayağa kalktığında aynı gözlem turu tekrarlanmalı ve bu rapor beşinci kez güncellenmelidir.
