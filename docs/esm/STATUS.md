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
- GPL-3.0 `D724Catalog 0.5.0` OPM paketi:
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
  - service/offering/item/schema create-update icin normalize audit olaylari ve mutation+audit transaction atomikligi,
  - alti test dosyasi, 73 paket testi, sonuc `PASS`,
  - authenticated customer HTTP katalog ve dinamik form smoke testleri.
- GPL-3.0 `D724Request 0.4.4` OPM paketi:
  - sunucu-tarafli dinamik cevap validasyonu ve workflow snapshot'i,
  - tenant/requester kapsamli idempotent form submission,
  - tenant-role onayi ve optimistic-lock durum gecisleri,
  - fulfillment gorevleri, basarisizlik ve otomatik fulfilled sonucu,
  - musteri makbuzu ve agent onay/fulfillment workbench'i,
  - request create, approval, first-response ve task/fulfillment yazimlarini audit append ile ayni DB transaction'inda commit/rollback,
  - oturumlu HTTP submit sonrasi `REQ-*` makbuzu ve agent gorunurluk testi.
- GPL-3.0 `D724Audit 0.1.3` OPM paketi:
  - tenant-bazli monoton sequence ve SHA-256 previous/event hash zinciri,
  - normalize actor/action/object/correlation/state/outcome/details kontrati,
  - source IP'nin salt'li SHA-256 pseudonym'i ve clear-text export yasagi,
  - `audit.read` policy kontrolu, tenant/object filtresi, cursor pagination ve NDJSON export,
  - tenant + `dedupe_key` benzersizligi ile tekrar teslimde ayni olay sonucunun donmesi,
  - request create/approve/first-response/task-transition/fulfilled adapter'lari,
  - zincir, head, sequence gap ve event hash dogrulayan `Verify` API'si,
  - iki test dosyasi, 29 test, sonuc `PASS`.
- GPL-3.0 `D724Catalog 0.5.0`, `D724Request 0.4.4` ve `D724Commitment 0.3.6` entegrasyonu:
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
  - atomik lease, exponential retry ve dead-letter escalation dispatcher,
  - tenant-role OTOBO email notification, tenant-kapsamli fulfillment assignment ve allow-list/HMAC-SHA256 webhook adapter'lari.
- Yedi D724 paketinde toplam 21 test dosyasi ve 369 test birlikte `PASS`.
- Gercek oturumlu HTTP kabul akisi `REQ-0000000086`: create, approve, first-response, task-completed ve fulfilled olaylari bes farkli dedupe anahtariyla kaydedildi; ayni customer POST replay'i ayni request'i dondurdu ve olay sayisi bes kaldi; tenant zinciri `Valid=1` ve request durumu `fulfilled`.
- Gercek hata enjeksiyonu `REQ-0000000102`: audit kapaliyken create icin tuketilen ID'de request/task/commitment/audit kalintisi `0`; ayni idempotency key ile retry basarili. Approval ve completed-task audit hatalarinda request/approval/task state ve version geri alindi; ayni optimistic version ile retry basarili, sonuc `fulfilled` ve uc commitment `met`.
- Concurrent dedupe kabulunde iki bagimsiz writer ayni tenant/key icin `replay=0` ve `replay=1` dondu; veritabaninda tek event, sequence/head `1` kaldi.
- Gercek katalog hata enjeksiyonu: service create audit hatasinda row `0`; update hatasinda ad/version degismedi; schema-set hatasinda schema row `0`. Ayni girdilerin retry'lari basarili oldu ve bes sirali katalog audit olayi uretildi; tenant zinciri `Valid=1`.
- Son OPM SHA-256 kaniti: Audit 0.1.3 `35f134fa68fae429e1f903cd2246a8d2127110adbf384af5768f35a85ce9b936`, Catalog 0.5.0 `36dbd28ec0035432b54ef7a7a807e316ad756d6cdd325a0ece55d32f6c50ae66`, Request 0.4.4 `2ceffaec696e20755fc8ee688507df6f45f38331c46e7ffaf4f6696bfcfff5c6`, Commitment 0.3.6 `a4dbc7ed1026bb89c5e9b425bfd2e832a3b412e19e5e3db136e09d2572176ede`.
- Gelistirme kurulumunda varsayilan admin ve root parolalarinin otomatik rotasyonu.

## Bilerek ertelenen

- Elasticsearch `search` profili opsiyoneldir. Test sunucusundaki Docker CDN baglantisi buyuk image katmaninda tekrar tekrar sifirlandigi icin temel kurulum aramadan dogrulanmistir.
- TLS ve genel internet yayini yapilmamistir; test erisimi ozel ag arayuzuyle sinirlidir.
- GitHub Actions workflow'u depoda bulunur ancak fork icin Actions calistirma politikasi ayrica etkinlestirilmelidir.
- Katalog repository'si merkezi tenant policy'ye baglanan ilk adapter'dir. OTOBO ticket, Generic Interface, daemon, rapor, cache ve search adapter'lari henuz baglanmamistir.
- OTOBO paket sema ceviricisi katalog parent'lari icin tanimlanan cok sutunlu foreign key'i ayri kisitlara cevirmektedir. Repository cifti birlikte dogrular; dogrudan DB yazimina karsi composite constraint sertlestirmesi release oncesi acik guvenlik isidir.
- OTOBO paket upgrade'inden sonra uzun omurlu Perl web worker'lari yeniden baslatilmalidir; aksi halde ayni anda eski ve yeni adapter kodu calisabilir. Test deploy runbook'u artik `web` ve `daemon` restart + HTTP health kontrolunu zorunlu kabul eder.
- Request lifecycle ve D724 katalog yonetimi mutasyonlari atomiktir. OTOBO ticket/article, Generic Interface, tenant directory ve commitment scheduler gibi diger yazim adapter'lari henuz ayni transaction/outbox completeness garantisine sahip degildir; zincir bu alanlarda olay eksiksizliginin tek basina kaniti sayilmaz.

## Henuz urun sayilmayan kapsam

Asagidaki maddeler tamamlanmadan ticari ESM `1.0` hedefi gerceklesmis sayilmaz:

- tenant/organizasyon policy siniri ve veri sizintisi testleri,
- UC hedefi, dead-letter replay arayuzu ve escalation teslim metrikleri,
- tum domain adapter'larinda atomik audit completeness, retention/legal hold ve dis WORM arsivi,
- portal ve agent urun deneyimi,
- SSO/SCIM ve entegrasyon sozlesmeleri,
- AI gateway, PII korumasi ve insan onayi,
- yedek/geri donus, upgrade, SBOM ve imzali release sureci.

Bir sonraki urun kapisi `AUD-01b-core`: cekirdek OTOBO mutasyon adapter'lari, transactional outbox ve immutable dis arsivdir.
