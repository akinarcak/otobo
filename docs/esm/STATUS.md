# D724 ESM Durum Kaydi

Son dogrulama: `2026-07-24`

## Calisan ve kanitlanmis

- OTOBO `rel-11_1` tabanli GitHub forku ve `codex/esm-foundation` gelistirme dali.
- Kaynak koddan uretilen `d724/esm:dev` container image'i.
- MariaDB, Redis, OTOBO web ve daemon servislerinden olusan izole Compose profili.
- Ozel test aginda HTTP health ve agent giris sayfasi: HTTP 200.
- OTOBO konsolundan SysConfig rebuild ve daemon status kontrolleri.
- GPL-3.0 `D724Foundation 0.1.0` OPM paketi:
  - urun ve edition SysConfig ayarlari,
  - telemetry icin opt-in varsayilani,
  - `Admin::D724::FoundationStatus --json` tanilama komutu,
  - paket deployment kontrolu `OK`,
  - iki test dosyasi, 15 test, sonuc `PASS`.
- Gelistirme kurulumunda varsayilan admin ve root parolalarinin otomatik rotasyonu.

## Bilerek ertelenen

- Elasticsearch `search` profili opsiyoneldir. Test sunucusundaki Docker CDN baglantisi buyuk image katmaninda tekrar tekrar sifirlandigi icin temel kurulum aramadan dogrulanmistir.
- TLS ve genel internet yayini yapilmamistir; test erisimi ozel ag arayuzuyle sinirlidir.
- GitHub Actions workflow'u depoda bulunur ancak fork icin Actions calistirma politikasi ayrica etkinlestirilmelidir.

## Henuz urun sayilmayan kapsam

Asagidaki maddeler tamamlanmadan ticari ESM `1.0` hedefi gerceklesmis sayilmaz:

- tenant/organizasyon policy siniri ve veri sizintisi testleri,
- hizmet portfoyu ve katalog veri modeli,
- talep, onay ve fulfillment orkestrasyonu,
- SLA/OLA taahhut motoru,
- audit event modeli ve disari aktarim,
- portal ve agent urun deneyimi,
- SSO/SCIM ve entegrasyon sozlesmeleri,
- AI gateway, PII korumasi ve insan onayi,
- yedek/geri donus, upgrade, SBOM ve imzali release sureci.

Bir sonraki kalite kapisi `SEC-01` tenant threat modeli ve policy servisinin reddetme-varsayilanli test matrisidir.
