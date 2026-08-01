# CareOnCloud ESM

CareOnCloud ESM, kurumların BT ve kurumsal hizmetlerini tek platformdan yönetmesi için geliştirilen, çok müşterili ve GPL-3.0 lisanslı bir Enterprise Service Management ürünüdür.

Ürün; hizmet kataloğu, talep ve vaka yönetimi, SLA taahhütleri, CMDB ve hizmet portföyü, Change/CAB, Problem ve Known Error yönetimi, tenant izolasyonu, OIDC/SCIM, API, webhook, denetim izi, raporlama, gözlemlenebilirlik ve akıllı ajan yardımcısını birlikte sunar.

## Ürün kimliği

- Ürün adı: **CareOnCloud ESM**
- Slogan: **Hizmet Bulutta, Kontrol Sizde.**
- Lisans: GNU General Public License v3.0 veya sonrası
- Üretici: Data Market Bilgi Hizmetleri A.Ş.
- Ürün adresi: [esm.arcak.net](https://esm.arcak.net)

CareOnCloud adı, logosu ve ticari hizmetleri GPL kapsamındaki yazılım lisansından ayrıdır. Community, Professional, Enterprise ve Managed sürümleri aynı GPL kaynak kodunu kullanır; ticari fark destek, işletim, entegrasyon, danışmanlık ve hizmet seviyesi sözleşmeleridir.

## Geliştirme

Ürüne özgü yetenekler `packages/D724*` altında sürümlenen CareOnCloud paketleri olarak geliştirilir. Yerel ve test ortamı profili `development/d724` altındadır. Mimari kararlar, güvenlik sınırları ve yayın durumu [docs/esm](docs/esm) dizininde tutulur.

Aktif geliştirme dalı `codex/esm-foundation` dalıdır. Katkılar GPL-3.0-or-later ile uyumlu olmalı; tenant izolasyonu, audit atomikliği ve çapraz müşteri erişim testlerini korumalıdır.

## Açık kaynak kökeni

Bu GitHub deposu [RotherOSS/otobo](https://github.com/RotherOSS/otobo) projesinden fork edilmiştir. Upstream proje ve önceki katkı sahiplerinin telif bildirimleri ilgili kaynak dosyalarında ve lisans kayıtlarında korunur. CareOnCloud ESM, Rother OSS GmbH tarafından onaylanmış veya desteklenmiş bir ürün değildir.

Dağıtım ve türev eser koşulları için [COPYING](COPYING), [LICENSE](LICENSE) ve [NOTICE](NOTICE) dosyalarına bakın.
