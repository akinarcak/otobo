# Marka temizliği yol haritası (otobo / d724 → CareOnCloud)

Hedef: `otobo` adı yalnızca GPL/telif bildirimlerinde, NOTICE/README köken atfında ve
süreli göç kodunun kontrollü izin listesinde kalsın; `d724` adı tamamen CareOnCloud olsun.
Kabul ölçütleri [BRAND-01](BRAND-01.md) dosyasındadır.

Ölçüm tabanı: `6bb5e38d8` (`codex/esm-foundation`), 4 Ağustos 2026.

## Hiç dokunulmayanlar

| Alan | Gerekçe |
|---|---|
| `LICENSE`, `COPYING*`, `NOTICE`, `AUTHORS.md` | GPL-3.0 ve telif atfı |
| `Copyright`, `otobo.io`, `Rother OSS`, `RotherOSS/otobo` içeren satırlar | Upstream telif bildirimi |
| `Kernel/cpan-lib/**` | Vendor edilmiş üçüncü taraf kod |
| `CHANGES.md` | Upstream sürüm geçmişi |
| `doc/sample_mails/**` | Testlerin bayt düzeyinde doğruladığı sabitler |

## Faz 1 — Ürün tanımı metinleri (tamamlandı)

Dosya başlıklarındaki ürün tanımı satırı ve modül yorumu değiştirildi.

- `OTOBO is a web-based ticketing system…` → `CareOnCloud ESM is a web-based ticketing system…`
- `# OTOBO modules` → `# CareOnCloud ESM modules`

Sonuç: 3069 dosyada 4227 değişiklik. Diff tam simetrik (4227 ekleme / 4227 silme,
satır sonu kayması yok), tüm değişen dosyalar geçerli UTF-8, marka sözleşmesi testi yeşil.

## Faz 2 — Serbest metin, yorum ve dokümantasyon (tamamlandı)

`Kernel/`, `scripts/`, `i18n/`, `docs/`, dotfile ve dockerfile içindeki düz anlatım.
Teknik anahtarlar dönüştürmeden önce maskelenip sonra geri konur.

Koruma listesi: `OTOBO_`, `otobo_`, `X-OTOBO-`, `::OTOBO`, `OTOBO::`, `Plugin/OTOBO`,
`MigrateFromOTRS/OTOBO`, `urn:otobo-com`, `Znuny4OTOBO`, `OTOBOCommunity`, `OTRSToOTOBO`,
`otobo-web|nginx|app|update|daemon`, `otobo.CodePolicy.pl`.

Sonuç: 784 dosyada 28025 satır. Düz metin kalıntısı 25.5k → 311.

### Bu fazda öğrenilen tuzaklar

Aşağıdakiler otomatik dönüştürmenin **dışında** tutulmalıdır; hepsi bu fazda gerçek
kırılmaya yol açtı ve geri alındı:

| Dosya | Neden |
|---|---|
| `development/careoncloud/Test-CareOnCloudBrand.ps1` | Yasaklı dize listesi kasıtlı olarak eski adları taşır; dönüştürülürse test tersini iddia eder |
| `development/careoncloud/migrate-careoncloud-brand.sh` | `OldDatabase='otobo'` varsayılanı; dönüştürülürse yanlış veritabanından göç eder |
| `docs/esm/branding/**` | Göç sürecini eski adlarla anlatır |
| `codepolicy/bin/otobo.CodePolicy.pl` | Dış `RotherOSS/codepolicy` deposunda, adı gerçekten böyle |
| Çevirmen e-postaları, `translate.otobo.org` | Gerçek kişi ve proje atfı |
| `https://github.com/akinarcak/otobo` | GPL köken atfı; depo gerçekten yeniden adlandırılmadıkça değişmez |
| `otobo_infotile` ve diğer `otobo_*` anahtarları | SysConfig anahtarı, veritabanında saklanır → Faz 4 |

Ayrıca: upstream projeden söz eden cümlelerde (“upstream OTOBO lisans denetleyicisi”)
`OTOBO` doğru kelimedir ve korunur.

## Faz 3 — Perl ad alanları ve dosya adları

`Kernel/System/SupportDataCollector/Plugin/OTOBO/**`, `Kernel/System/MigrateFromOTRS/OTOBO*.pm`,
`Kernel/Output/Template/Plugin/OTOBO.pm`, `Znuny4OTOBO*`, `scripts/test/SysConfig/OTOBOCommunity/**`.

Bu faz i18n dosyalarındaki yaklaşık 6000 `#. Perl Module: …OTOBO…` referans yorumunu da
kendiliğinden temizler; çeviri dosyaları ayrıca elle düzenlenmemelidir.

Dikkat: destek verisi tanımlayıcıları modül adından türetilir; destek paketi çıktısını
doğrulayan testler birlikte güncellenmelidir.

## Faz 4 — Şablon değişkenleri ve mail başlıkları (tamamlandı, veri göçü bekliyor)

Karar: **tam temizlik**, geriye dönük alias yok. Kodda ve tohum veride şu adlar değişti:

| Eski | Yeni | Nerede saklanır |
|---|---|---|
| `OTOBO_*` smart tag | `CareOnCloud_*` | bildirim gövdeleri, otomatik yanıtlar, selamlama, imza, şablon |
| `X-OTOBO-*` | `X-CareOnCloud-*` | PostMaster filtreleri, `PostmasterX-Header` ayarı |
| `otobo_config` | `careoncloud_config` | SysConfig XML kök elemanı (37 dosya + ayrıştırıcı) |
| `otobo_stats` | `careoncloud_stats` | dışa aktarılmış istatistik XML'i |
| `otobo_infotile` | `careoncloud_infotile` | `xml_storage` satırları |
| `urn:otobo-com` | `urn:careoncloud-com` | örnek SOAP ad alanı |

### Veri göçü zorunludur

Alias bırakılmadığı için, **göç çalıştırılmadan mevcut veritabanındaki şablonlar bozulur**:
`<OTOBO_TICKET_...>` etiketleri artık çözümlenmez ve `X-OTOBO-*` başlıkları tanınmaz.

```bash
bin/careoncloud.Console.pl Maint::CareOnCloud::MigrateBrandTags            # kuru çalışma
bin/careoncloud.Console.pl Maint::CareOnCloud::MigrateBrandTags --execute
bin/careoncloud.Console.pl Maint::Config::Rebuild
```

Komut varsayılan olarak yalnızca rapor verir. Şu tabloları günceller:
`notification_event_message`, `auto_response`, `salutation`, `signature`,
`standard_template`, `postmaster_filter`, `sysconfig_modified`, `xml_storage`.

Doğrulanmamış nokta: komut bu geliştirme makinesinde **çalıştırılamadı** (Perl/Docker yok).
Yalnızca yapısal denetimden geçti. İlk çalıştırma kopya bir veritabanında, önce kuru
çalışma ile yapılmalıdır.

## Faz 5 — Docker imaj yolları ve CI

`careoncloud.web.dockerfile` içindeki `/opt/otobo_install`, `otobo_next`, `otobo-web` hedefi ve
`.github/` içindeki `otobo_build_date`, `otobo_branch`, `otobo_commit`, `otobo_ref` değişkenleri.
Dockerfile, `bin/docker/entrypoint.sh` ve iş akışları **birlikte** değişmelidir; aksi halde imaj
derlemesi kırılır. Değişiklikten sonra imaj yeniden derlenip aday etiketiyle doğrulanmalıdır.

## Faz 6 — d724 → CareOnCloud (depo tarafı tamamlandı, veri göçü bekliyor)

259 yol ve 2826 satır çevrildi: `packages/D724*` → `packages/CareOnCloud*` (18 paket),
`development/d724/` → `development/careoncloud/`, `.github/workflows/d724-foundation.yml`,
Perl ad alanları (`Kernel/System/D724/` → `Kernel/System/CareOnCloud/`,
`AdminD724Catalog` → `AdminCareOnCloudCatalog`), `.sopm` paket adları, 39 tablo adı ve
62 SysConfig ayar anahtarı.

### Veri göçü zorunludur

d724 yalnızca kodda değil, **veritabanında** da yaşıyor:

| Nerede | Adet |
|---|---|
| `d724_*` tabloları (dolu: 3680 denetim olayı, 860 hizmet, 212 katalog kalemi …) | 39 |
| `D724::` önekli SysConfig ayarları | 62 |
| `package_repository` içindeki paket kayıtları ve gömülü `.sopm` içeriği | 18 |

OTOBO'da paket yeniden adlandırma diye bir işlem yoktur; kaldır-kur yapılırsa
`DatabaseUninstall` tabloları **düşürür ve veriyi yok eder**. Bu yüzden göç komutu paketi
hiç kaldırmaz, satırları yerinde çevirir ve tabloları `RENAME TABLE` ile taşır:

```bash
bin/careoncloud.Console.pl Maint::CareOnCloud::MigratePackageNamespace            # kuru çalışma
bin/careoncloud.Console.pl Maint::CareOnCloud::MigratePackageNamespace --execute
bin/careoncloud.Console.pl Maint::Config::Rebuild
```

Hedef tablo zaten varsa komut çalışmayı reddeder; sessizce gölgelenmiş veri riskini almaz.
Web ve daemon durdurulmuşken çalıştırılmalıdır.

### Compose proje adı değişti

`development/careoncloud/compose.yml` artık `name: careoncloud-esm`. Canlı yığın hâlâ
`d724-esm` projesinde ve verisi `d724-esm_careoncloud-app` / `d724-esm_careoncloud-update`
volume'lerinde. Yeni adla compose çalıştırmak **boş yeni bir yığın** açar; eski veriyi
`migrate-careoncloud-brand.sh` ile kopyalamadan eski projeyi kaldırmayın.

## Her fazdan sonra

```powershell
powershell -ExecutionPolicy Bypass -File development\careoncloud\Test-CareOnCloudBrand.ps1
```

Testin yasaklı yol ve yasaklı dize listesi, o fazda temizlenen kalemlerle genişletilmelidir;
böylece temizlik geri gelmeyecek şekilde kilitlenir.
