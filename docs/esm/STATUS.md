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
- GPL-3.0 `D724TenantDirectory 0.2.1` OPM paketi:
  - kalici tenant ve agent-role membership tablolari,
  - directory-derived agent policy context'i,
  - one-time confirmed bootstrap ve tenant/member mutation audit olaylari,
  - membership optimistic version'i ve idempotent grant/revoke replay'i,
  - tenant-row `FOR UPDATE` kilidi ile last-admin revoke yarisi ve tenant self-deactivation lockout engelleri,
  - domain mutation ile audit head/event append'inin tek transaction'da commit/rollback garantisi,
  - audit kapali grant/revoke hata enjeksiyonunda satir ve version rollback'i; ayni girdinin retry basarisi,
  - dort test dosyasi, 57 test, sonuc `PASS`.
- GPL-3.0 `D724Catalog 0.5.2` OPM paketi:
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
- GPL-3.0 `D724Request 0.4.6` OPM paketi:
  - sunucu-tarafli dinamik cevap validasyonu ve workflow snapshot'i,
  - tenant/requester kapsamli idempotent form submission,
  - tenant-role onayi ve optimistic-lock durum gecisleri,
  - fulfillment gorevleri, basarisizlik ve otomatik fulfilled sonucu,
  - musteri makbuzu ve agent onay/fulfillment workbench'i,
  - request create, approval, first-response ve task/fulfillment yazimlarini audit append ile ayni DB transaction'inda commit/rollback,
  - oturumlu HTTP submit sonrasi `REQ-*` makbuzu ve agent gorunurluk testi.
- GPL-3.0 `D724Audit 0.2.0` OPM paketi:
  - tenant-bazli monoton sequence ve SHA-256 previous/event hash zinciri,
  - normalize actor/action/object/correlation/state/outcome/details kontrati,
  - source IP'nin salt'li SHA-256 pseudonym'i ve clear-text export yasagi,
  - `audit.read` policy kontrolu, tenant/object filtresi, cursor pagination ve NDJSON export,
  - tenant + `dedupe_key` benzersizligi ile tekrar teslimde ayni olay sonucunun donmesi,
  - request, katalog ve tenant-directory mutation adapter'lari,
  - temel katman olarak tenant-directory paketine statik bagimlilik olmadan subject veya opsiyonel directory-derived authorization,
  - zincir, head, sequence gap ve event hash dogrulayan `Verify` API'si,
  - iki test dosyasi, 29 test, sonuc `PASS`.
- GPL-3.0 `D724TicketAudit 0.6.1` OPM paketi:
  - resmi `Ticket::CustomModule` extension noktasi ile cekirdek dosya fork'u olmadan repository wrapping,
  - her OTOBO ticket icin immutable `d724_ticket_scope` tenant binding ve monoton mutation version'i,
  - ticket create ile title/queue/customer/lock/state/owner/responsible/priority mutasyonlarinda domain+scope+audit tek transaction,
  - Email/Internal/Phone ortak MIME article create yolunda DB-storage zorunlulugu ve body icermeyen normalize audit,
  - audit hata enjeksiyonunda ticket state, article row/storage, customer migration, scope version ve cache rollback kaniti,
  - tenantless create ve cross-tenant customer reassignment icin fail-closed davranis,
  - toplu active-tenant backfill ve acik onayli tek-ticket CustomerID replacement komutlari,
  - status kapisinda `UnboundTickets=0`, `InvalidTenantTickets=0`,
  - sorgu-oncesi tenant filtresi, `CustomerIDRaw` bypass reddi ve immutable-scope tekil okuma,
  - Generic Interface get/history/update ortak erisiminde OTOBO izni + tenant izni birlikte zorunlu,
  - uc test dosyasi / 84 test `PASS`.
- GPL-3.0 `D724Catalog 0.5.2`, `D724Request 0.4.6` ve `D724Commitment 0.3.8` entegrasyonu:
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
- Sekiz D724 paketinde toplam 26 test dosyasi ve 486 test birlikte `PASS`.
- Gercek oturumlu HTTP kabul akisi `REQ-0000000086`: create, approve, first-response, task-completed ve fulfilled olaylari bes farkli dedupe anahtariyla kaydedildi; ayni customer POST replay'i ayni request'i dondurdu ve olay sayisi bes kaldi; tenant zinciri `Valid=1` ve request durumu `fulfilled`.
- Gercek hata enjeksiyonu `REQ-0000000102`: audit kapaliyken create icin tuketilen ID'de request/task/commitment/audit kalintisi `0`; ayni idempotency key ile retry basarili. Approval ve completed-task audit hatalarinda request/approval/task state ve version geri alindi; ayni optimistic version ile retry basarili, sonuc `fulfilled` ve uc commitment `met`.
- Concurrent dedupe kabulunde iki bagimsiz writer ayni tenant/key icin `replay=0` ve `replay=1` dondu; veritabaninda tek event, sequence/head `1` kaldi.
- Gercek katalog hata enjeksiyonu: service create audit hatasinda row `0`; update hatasinda ad/version degismedi; schema-set hatasinda schema row `0`. Ayni girdilerin retry'lari basarili oldu ve bes sirali katalog audit olayi uretildi; tenant zinciri `Valid=1`.
- Gercek directory audit hata enjeksiyonu: audit kapaliyken membership grant `AUDIT_WRITE_FAILED` ve kalici row `0`; revoke hatasinda membership `active/version=1` kaldi. Audit geri geldiginde retry'lar `version=1` ve `version=2` ile basarili oldu; zincirde yalniz `tenant.created`, `tenant.membership.granted`, `tenant.membership.revoked` olaylari kaldi ve `Verify.Valid=1`.
- Gercek OTOBO ticket kabul akisi: demo tenant ticket `D724AUD20260724001` / ID `9`, `open`, scope version `3`; `ticket.created`, `ticket.state.updated`, `ticket.article.created` olaylari ve gecerli tenant zinciri. Idempotent ikinci kabul calismasi `Created=0` ile ayni ticket ve uc olayi dondurdu.
- Legacy upgrade kabulunde bos CustomerID'li kurulum ticket'i `2015071510123456` acik replacement onayiyla `d724-demo` tenant'ina transaction-atomic atandi; iki cekirdek ticket'in ikisi de scoped, unbound/invalid sayilari `0`.
- Son OPM SHA-256 kaniti: Audit 0.2.0 `44604ad6aeb20d5e9eda2c25b28423f2eb6082037d06061f154b8fab13d4446d`, TenantDirectory 0.2.1 `024cfa1cc1298bd00459cc6cb88ecc99e868caac1beb9fa434dd814d06be7b28`, Catalog 0.5.2 `90dfeb6309bcaa89bcffe9acff4ec7e92031afff4bec7eb34bb313343a2795e5`, Request 0.4.6 `c8b5ddb9a9a0aed10e43094f9748ea7a6aca2089f41c0097236f6b57a7c51f46`, Commitment 0.3.8 `19bb3331b3efee9c3d143673fc7537720d3d98f11fc3bf69fa24f3c9229eb94c`.
- TicketAudit 0.6.1 OPM SHA-256 son release build'inde yeniden kaydedilecektir.
- Gelistirme kurulumunda varsayilan admin ve root parolalarinin otomatik rotasyonu.

## Bilerek ertelenen

- Elasticsearch `search` profili opsiyoneldir. Test sunucusundaki Docker CDN baglantisi buyuk image katmaninda tekrar tekrar sifirlandigi icin temel kurulum aramadan dogrulanmistir.
- TLS ve genel internet yayini yapilmamistir; test erisimi ozel ag arayuzuyle sinirlidir.
- GitHub Actions workflow'u depoda bulunur ancak fork icin Actions calistirma politikasi ayrica etkinlestirilmelidir.
- Katalog, cekirdek OTOBO ticket yazimlari, TicketSearch ve Generic Interface ortak ticket get/history/update erisimi tenant scope'a baglidir. Generic Interface operasyon-bazli role/action, daemon, rapor, cache ve Elasticsearch adapter'lari henuz merkezi policy'ye tam baglanmamistir.
- OTOBO paket sema ceviricisi katalog parent'lari icin tanimlanan cok sutunlu foreign key'i ayri kisitlara cevirmektedir. Repository cifti birlikte dogrular; dogrudan DB yazimina karsi composite constraint sertlestirmesi release oncesi acik guvenlik isidir.
- OTOBO paket upgrade'inden sonra uzun omurlu Perl web worker'lari yeniden baslatilmalidir; aksi halde ayni anda eski ve yeni adapter kodu calisabilir. Test deploy runbook'u artik `web` ve `daemon` restart + HTTP health kontrolunu zorunlu kabul eder.
- Request lifecycle, D724 katalog, tenant-directory ve kapsanan OTOBO ticket/MIME article mutasyonlari atomiktir. Ticket delete/merge/type/service/SLA/pending, Chat article, Generic Interface ve commitment scheduler gibi diger yazim adapter'lari henuz ayni transaction/outbox completeness garantisine sahip degildir.

## Henuz urun sayilmayan kapsam

Asagidaki maddeler tamamlanmadan ticari ESM `1.0` hedefi gerceklesmis sayilmaz:

- tenant/organizasyon policy siniri ve veri sizintisi testleri,
- UC hedefi, dead-letter replay arayuzu ve escalation teslim metrikleri,
- tum domain adapter'larinda atomik audit completeness, retention/legal hold ve dis WORM arsivi,
- portal ve agent urun deneyimi,
- SSO/SCIM ve entegrasyon sozlesmeleri,
- AI gateway, PII korumasi ve insan onayi,
- yedek/geri donus, upgrade, SBOM ve imzali release sureci.

Bir sonraki urun kapisi genel `SEC-01b/API-01`: daemon/report/cache/Elasticsearch adapter'lari ile OAuth client, operasyon-bazli role/action, rate limit ve surumlu REST kontrati; buna paralel kalan ticket/Chat/SLA adapter'lari, transactional outbox ve immutable dis arsivdir.
