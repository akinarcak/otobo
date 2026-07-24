# AUD-01b Tenant Directory Atomic Audit

Durum: tamamlandi (`2026-07-24`).

## Kapsam

`D724TenantDirectory 0.2.1` su tenant-kapsamli mutation'lari normalize audit zincirine baglar:

- `tenant.created`
- `tenant.updated`
- `tenant.membership.granted`
- `tenant.membership.revoked`

Tenant nesneleri tenant key'i, membership nesneleri `user_id:role` kimligi ile temsil edilir. Dedupe anahtari tenant version'i veya membership version'i tasir. Ayni active grant ya da revoked revoke replay'i version ve audit sequence ilerletmez.

## Transaction ve lock garantisi

Public tenant/membership yazimlari production `AutoCommit` baglantisinda transaction acar. Domain satiri, optimistic version ve audit head/event ayni transaction'da commit edilir. Audit disabled veya append hatasinda mutasyon rollback edilir. Bir ust transaction varsa servis ona katilir ve commit sahipligini devralmaz.

Membership grant/revoke, tenant satirini `SELECT ... FOR UPDATE` ile kilitler. Last-admin sayimi bu kilidin altinda yapilir; ayni tenant'taki eszamanli membership yazarlari serialize edilir. Tenant self-deactivation ayrica platform-admin kararina tabidir.

## Katmanlama

Audit temel paketi directory'ye statik olarak bagli degildir. Hazir bir `Subject` ile dogrudan policy karari verir; yalniz `UserID` tabanli cagrida directory nesnesini dinamik olarak cozer. Directory paketi Audit 0.2.0'a baglanir. Bu yon, paket bagimlilik dongusunu engeller.

## Kanit

- Directory paketi: 4 dosya / 57 test `PASS`.
- Tum D724 regresyonu: 23 dosya / 402 test `PASS`.
- MariaDB upgrade'i mevcut membership satirlarina `version=1` geri doldurdu.
- Production-style audit fault injection:
  - grant hatasi `AUDIT_WRITE_FAILED`, membership row sayisi `0`;
  - grant retry basarili, version `1`;
  - revoke hatasi `AUDIT_WRITE_FAILED`, durum/version `active/1`;
  - revoke retry basarili, version `2`;
  - zincirde yalniz created/granted/revoked olaylari ve `Verify.Valid=1`.
- Kurulu OPM SHA-256: `024cfa1cc1298bd00459cc6cb88ecc99e868caac1beb9fa434dd814d06be7b28`.

## Acik core kapsam

Clustered iki-proses last-admin yarisi icin kabul testi, Generic Interface, kalan ticket/Chat ve commitment scheduler/escalation audit completeness, retention/legal hold ve dis WORM sink sonraki core kapilaridir. OTOBO ticket/MIME article cekirdegi daha sonra `AUD-01b-ticket-core` kapsaminda tamamlanmistir.
