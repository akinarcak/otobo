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
- GPL-3.0 `D724TenantGuard 0.2.0` OPM paketi:
  - varsayilan-reddet action/role matrisi,
  - exact ve buyuk/kucuk harf duyarli tenant siniri,
  - query'ler icin fail-closed `ScopeGet`,
  - varsayilan kapali global platform admin gecisi,
  - karar neden kodlari ve JSON tanilama komutu,
  - tenant-bazli role bindings ile multi-tenant privilege bleed engeli,
  - iki test dosyasi, 86 test, sonuc `PASS`,
  - ayni tenant karari `ALLOW_ROLE_ACTION`, capraz tenant karari `DENY_CROSS_TENANT`.
- GPL-3.0 `D724TenantDirectory 0.1.2` OPM paketi:
  - kalici tenant ve agent-role membership tablolari,
  - directory-derived agent policy context'i,
  - one-time confirmed bootstrap ve audited membership grant komutlari,
  - last tenant-admin revoke ve tenant self-deactivation lockout engelleri,
  - iki test dosyasi, 24 test, sonuc `PASS`.
- GPL-3.0 `D724Catalog 0.4.0` OPM paketi:
  - Service, ServiceOffering ve CatalogItem MariaDB semasi,
  - tenant-guarded create/get/list/update repository API'si,
  - tenant icinde benzersiz key, lifecycle ve optimistic version kontrolu,
  - versioned ve whitelist-validasyonlu dinamik form semasi,
  - authenticated customer session'dan tenant tureten katalog portal modulu,
  - yalnizca tam aktif hierarchy listeleme ve parent availability kontrolu,
  - HTML escape ve gercek OTOBO template render testleri,
  - tenant directory context'inden beslenen agent yonetim ekrani,
  - Service/Offering/Item lifecycle ve JSON form semasi yonetimi,
  - CSRF challenge token ve optimistic update formlari,
  - bes test dosyasi, 59 paket testi, sonuc `PASS`,
  - authenticated customer HTTP katalog ve dinamik form smoke testleri.
- GPL-3.0 `D724Request 0.2.0` OPM paketi:
  - sunucu-tarafli dinamik cevap validasyonu ve workflow snapshot'i,
  - tenant/requester kapsamli idempotent form submission,
  - tenant-role onayi ve optimistic-lock durum gecisleri,
  - fulfillment gorevleri, basarisizlik ve otomatik fulfilled sonucu,
  - musteri makbuzu ve agent onay/fulfillment workbench'i,
  - oturumlu HTTP submit sonrasi `REQ-*` makbuzu ve agent gorunurluk testi.
- GPL-3.0 `D724Catalog 0.4.0`, `D724Request 0.2.0` ve `D724Commitment 0.2.1` entegrasyonu:
  - tenant-local commitment policy referansli katalog workflow'u,
  - request acilisinda immutable policy snapshot ve otomatik commitment baslatma,
  - OTOBO calisma saatleri, tatil gunleri ve calendar timezone hesaplari,
  - request status kurallarindan pause/resume ve due-time yeniden hesaplama,
  - warning/breach optimistic transition ve append-only system actor kaniti,
  - daemon tarafindan dakikada bir, tek paralel instance ile scheduled sweep,
  - tenant-admin policy ekrani; customer ve agent warning/due/status gorunumu,
  - authenticated HTTP akisi: `paused -> running -> met` ve `awaiting_approval -> in_fulfillment -> fulfilled`.
  - response/resolution/OLA hedefleri, validated-answer entitlement secimi ve idempotent escalation outbox,
  - authenticated HTTP akisi `REQ-0000000042`: iki hedef paused, onaydan sonra uc hedef running, ilk yanit ve fulfillment sonunda uc hedef met.
- Alti D724 paketinde toplam 17 test dosyasi ve 297 test birlikte `PASS`.
- Tekrarlanabilir OPM SHA-256 kaniti: Catalog 0.4.0 `db3f490b52cc1b765b7c03240fc22e219f5edbe0989f0ce3cf7f9e888a73035d`, Request 0.2.0 `44c2c508eee36cd0d0d8de961dcb2e00dd080b564b6d3af2461b3943c35a0bf8`, Commitment 0.2.1 `73aa20b69d20bb84f4b8f1a236e9e42d1670bc8c14fa028aa9096a271234325f`.
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
- escalation outbox teslim worker'i, notification/assignment/imzali webhook adapter'lari ve UC hedefi,
- audit event modeli ve disari aktarim,
- portal ve agent urun deneyimi,
- SSO/SCIM ve entegrasyon sozlesmeleri,
- AI gateway, PII korumasi ve insan onayi,
- yedek/geri donus, upgrade, SBOM ve imzali release sureci.

Bir sonraki urun kapisi `SLA-01b-actions` gercek escalation dispatcher ve teslim kanitidir. Ardindan `AUD-01` normalize audit event modeline gecilir.
