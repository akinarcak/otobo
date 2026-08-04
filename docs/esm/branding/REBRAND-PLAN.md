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
| `development/d724/Test-CareOnCloudBrand.ps1` | Yasaklı dize listesi kasıtlı olarak eski adları taşır; dönüştürülürse test tersini iddia eder |
| `development/d724/migrate-careoncloud-brand.sh` | `OldDatabase='otobo'` varsayılanı; dönüştürülürse yanlış veritabanından göç eder |
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

## Faz 4 — Şablon değişkenleri (canlı veri göçü gerektirir)

`OTOBO_TICKET_*`, `OTOBO_CONFIG_*`, `OTOBO_AGENT_*`, `OTOBO_APPOINTMENT_*`,
`OTOBO_MERGE_TO_TICKET` ve benzerleri **üretim veritabanındaki satırların içinde** durur:
bildirim gövdeleri, otomatik yanıtlar, selamlamalar, imzalar, şablonlar.

Önerilen yaklaşım — çift destek:

1. `CareOnCloud_*` biçimi kanonik hale getirilir.
2. `OTOBO_*` biçimi geriye dönük alias olarak çözümlenmeye devam eder.
3. DB içeriğini yeni biçime çeviren bir göç betiği yazılır ve önce kopya ortamda çalıştırılır.
4. Alias tablosu, kullanım gözlendikten sonra planlı bir sürümde kaldırılır.

Kod tarafında `otobo` yalnızca bu alias tablosunda kalır; bu, BRAND-01'in izin verdiği
"süreli göç kodu" istisnasıdır.

## Faz 5 — Docker imaj yolları ve CI

`careoncloud.web.dockerfile` içindeki `/opt/otobo_install`, `otobo_next`, `otobo-web` hedefi ve
`.github/` içindeki `otobo_build_date`, `otobo_branch`, `otobo_commit`, `otobo_ref` değişkenleri.
Dockerfile, `bin/docker/entrypoint.sh` ve iş akışları **birlikte** değişmelidir; aksi halde imaj
derlemesi kırılır. Değişiklikten sonra imaj yeniden derlenip aday etiketiyle doğrulanmalıdır.

## Faz 6 — d724 → CareOnCloud

`packages/D724*` (18 paket), `development/d724/`, `.github/workflows/d724-foundation.yml`,
`D724Problem-*-source.tar.gz`.

Paket adı kurulu sistemlerde veritabanına yazılıdır; dizin ve `.sopm` adını değiştirmek tek
başına yetmez, paket yeniden adlandırma/göç adımı gerekir. Perl ad alanları ayrı bir adımda
ele alınmalıdır.

## Her fazdan sonra

```powershell
powershell -ExecutionPolicy Bypass -File development\d724\Test-CareOnCloudBrand.ps1
```

Testin yasaklı yol ve yasaklı dize listesi, o fazda temizlenen kalemlerle genişletilmelidir;
böylece temizlik geri gelmeyecek şekilde kilitlenir.
