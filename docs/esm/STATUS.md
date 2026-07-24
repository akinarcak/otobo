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
- GPL-3.0 `D724TenantGuard 0.1.1` OPM paketi:
  - varsayilan-reddet action/role matrisi,
  - exact ve buyuk/kucuk harf duyarli tenant siniri,
  - query'ler icin fail-closed `ScopeGet`,
  - varsayilan kapali global platform admin gecisi,
  - karar neden kodlari ve JSON tanilama komutu,
  - iki test dosyasi, 78 test, sonuc `PASS`,
  - ayni tenant karari `ALLOW_ROLE_ACTION`, capraz tenant karari `DENY_CROSS_TENANT`.
- GPL-3.0 `D724Catalog 0.1.0` OPM paketi:
  - Service, ServiceOffering ve CatalogItem MariaDB semasi,
  - tenant-guarded create/get/list/update repository API'si,
  - tenant icinde benzersiz key, lifecycle ve optimistic version kontrolu,
  - iki test dosyasi, 30 entegrasyon testi, sonuc `PASS`,
  - capraz tenant okuma ve parent baglama negatif testleri.
- Gelistirme kurulumunda varsayilan admin ve root parolalarinin otomatik rotasyonu.

## Bilerek ertelenen

- Elasticsearch `search` profili opsiyoneldir. Test sunucusundaki Docker CDN baglantisi buyuk image katmaninda tekrar tekrar sifirlandigi icin temel kurulum aramadan dogrulanmistir.
- TLS ve genel internet yayini yapilmamistir; test erisimi ozel ag arayuzuyle sinirlidir.
- GitHub Actions workflow'u depoda bulunur ancak fork icin Actions calistirma politikasi ayrica etkinlestirilmelidir.
- Katalog repository'si merkezi tenant policy'ye baglanan ilk adapter'dir. OTOBO ticket, Generic Interface, daemon, rapor, cache ve search adapter'lari henuz baglanmamistir.
- OTOBO paket sema ceviricisi katalog parent'lari icin tanimlanan cok sutunlu foreign key'i ayri kisitlara cevirmektedir. Repository cifti birlikte dogrular; dogrudan DB yazimina karsi composite constraint sertlestirmesi release oncesi acik guvenlik isidir.

## Henuz urun sayilmayan kapsam

Asagidaki maddeler tamamlanmadan ticari ESM `1.0` hedefi gerceklesmis sayilmaz:

- tenant/organizasyon policy siniri ve veri sizintisi testleri,
- katalog yonetim arayuzu, portal ve dinamik form semasi,
- talep, onay ve fulfillment orkestrasyonu,
- SLA/OLA taahhut motoru,
- audit event modeli ve disari aktarim,
- portal ve agent urun deneyimi,
- SSO/SCIM ve entegrasyon sozlesmeleri,
- AI gateway, PII korumasi ve insan onayi,
- yedek/geri donus, upgrade, SBOM ve imzali release sureci.

Bir sonraki urun kapisi `CAT-02` portal katalog listeleme, yonetim arayuzu ve dinamik form semasidir. Katalog repository'si `SEC-01b` icin ilk gercek veri erisim adapter'i olarak tamamlanmistir.
