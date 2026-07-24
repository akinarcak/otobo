# D724 ESM Foundation

Bu dizin, OTOBO `rel-11_1` tabani uzerinde gelistirilecek ticari ESM urununun karar kaydidir. `D724 ESM` gelistirme kod adidir; genel kullanima acilmadan once marka arastirmasi yapilarak kalici urun adi secilmelidir.

## Urun ilkeleri

1. OTOBO cekirdegi mumkun oldugunca degistirilmez; fark yaratan ozellikler surumlenebilir paketler ve acik arabirimlerle eklenir.
2. Dagitilan urun ve turev kod GPL-3.0 kapsaminda kalir. Gelir; yonetilen hizmet, kurulum, destek, egitim, entegrasyon ve SLA paketlerinden uretilir.
3. Ilk pazar, 100-5.000 kullanicili kurumlar ve MSP'lerdir. Urun Turkce ve Ingilizceyi birinci sinif dil olarak destekler.
4. Her is akisi olculebilir SLA, sahiplik, denetim izi ve yetki siniri tasir.
5. Yapay zeka karar vermez; onerir, kaynak gosterir ve insan onayi ile calisir.

## Belgeler

- [PRODUCT.md](PRODUCT.md): urun kapsami, kisiler ve moduller
- [ARCHITECTURE.md](ARCHITECTURE.md): teknik sinirlar ve hedef mimari
- [ROADMAP.md](ROADMAP.md): surumlar, epic'ler ve basari olcutleri
- [GPL-COMMERCIAL.md](GPL-COMMERCIAL.md): ticari model ve uyum kontrol listesi
- [STATUS.md](STATUS.md): dogrulanmis mevcut durum ve acik kapsam

## Gelistirme modeli

- `upstream`: `RotherOSS/otobo`
- `origin`: urun forku
- `rel-11_1`: upstream ile eslenen temel dal
- `codex/esm-foundation`: ilk urun tasarimi dali
- Ozellik dallari: `codex/esm-<epic>-<kisa-ad>`

Her upstream guncellemesi once temiz temel dala alinmali, ardindan urun paketleriyle entegrasyon testinden gecirilmelidir. Yeni urun davranisi icin once OTOBO paket/Generic Interface noktasi kullanilir; cekirdek yamasi ancak uzatma noktasi yoksa ve karar kaydi yazildiysa kabul edilir.
