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

## Faz 2 — Serbest metin, yorum ve dokümantasyon

`Kernel/`, `scripts/`, `docs/`, dotfile ve dockerfile içindeki düz anlatım. Teknik anahtar
biçimleri (aşağıdaki koruma listesi) regex ile dışarıda bırakılmalıdır.

Koruma listesi: `OTOBO_[A-Za-z]`, `X-OTOBO-`, `::OTOBO`, `/OTOBO/`, `OTOBO.` (JS ad alanı),
`urn:otobo-com:`, `TidyAll::Plugin::OTOBO`, `Znuny4OTOBO`, `OTOBOCommunity`, `OTRSToOTOBO`.

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
