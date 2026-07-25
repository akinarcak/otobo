# SEC-01b Daemon Tenant Policy

Durum: daemon/automation alt kapisi tamamlandi (`2026-07-25`). Genel
`SEC-01b`, cache, search ve kalan domain adapter'lari tamamlanana
kadar aciktir.

## Guvenlik sozlesmesi

`D724TenantGuard 0.4.0` policy contract `1.3.0`, bir arka plan isi tenant verisine dokunmadan once
`AutomationAuthorize(TenantID, JobName)` karari ister. Karar:

- dar tenant/job kimlik formatini dogrular;
- tenant'in veritabaninda mevcut ve `active` oldugunu dogrular;
- yalniz o tenant'a bagli `automation:<job>` subject'i uretir;
- merkezi, default-deny `automation.execute` role/action kararini calistirir;
- policy kapaliysa, sorgu basarisizsa veya tenant pasifse is vermeden reddeder.

Bu subject istemciden veya daemon payload'undan alinmaz; guvenilir calisma
zamaninda uretilir. `platform_admin` bypass'i kullanmaz.

## Baglanan isler

- `D724Commitment::Sweep`: her runnable commitment satiri icin karar alir;
  reddedilen satir state/version veya event uretemez. Basarili olay aktoru
  `automation:commitment-sweep` olur.
- `D724EscalationDispatcher::Dispatch`: her pending/retry outbox satirini lease
  etmeden once karar alir; reddedilen teslimat pending ve lease'siz kalir.
- `D724Webhook::Scan`: her aktif subscription icin audit okumadan ve cursor
  ilerletmeden once karar alir.

Her is `Denied` ve `Errors` sayaclarini doner; herhangi bir policy reddi daemon
run sonucunu basarisiz yapar. `CommitmentStatus`, runnable commitment veya
dispatchable outbox satirinin aktif tenant'i yoksa; `WebhookStatus` aktif
subscription pasif/eksik tenant'a bagliysa fail-closed olur.

## Kanit

Gercek MariaDB entegrasyon testleri tenant'i pasif duruma getirip sunlari
dogruladi:

- commitment state ve optimistic version degismedi;
- webhook subscription cursor'u ilerlemedi;
- escalation outbox satiri lease edilmedi ve `pending` kaldi;
- policy kapaliyken automation context uretilmedi;
- normal aktif tenant sweep, scan ve delivery akislari geriye uyumlu kaldi.

Guncel paket regresyonu 41 dosya ve 834 assertion ile gecti.
