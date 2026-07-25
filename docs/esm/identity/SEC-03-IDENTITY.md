# SEC-03 Birleşik Kimlik Güven Sınırı

`D724Identity`, CareOnCloud ESM'in OIDC/SAML ve sonraki SCIM adaptörleri için tenant-safe çekirdek sözleşmesidir. Ham token doğrulamaz; yalnız imza, issuer, audience, süre ve nonce kontrollerini tamamlamış bir protokol adaptörünün `Verification` sonucunu kabul eder.

## Değişmezler

- Tenant hiçbir zaman token içindeki serbest `tenant_id` claim'inden seçilmez.
- Tenant, veritabanında benzersiz olan exact `(issuer, audience)` trust route'undan türetilir.
- Yalnız HTTPS issuer kabul edilir; query/fragment ve wildcard issuer yasaktır.
- E-posta domain'i provider allow-list'inde olmalıdır.
- Grup→rol eşlemesi yalnız bilinen tenant rollerine yapılabilir; eşleşmeyen gruplar yetki kazandırmaz.
- Her kimlik varsayılan `requester` rolüyle başlar.
- `(provider, subject)` bağı değişmezdir. Subject farklı login'e, aynı tenant login'i farklı subject'e bağlanamaz.
- Provider oluşturma ve ilk subject link'i audit olayıyla aynı transaction'dadır.

## Tamamlanan kapsam

- Tenant-admin korumalı provider trust route oluşturma.
- OIDC/SAML verifier sonucu için fail-closed claim çözümleme.
- Domain allow-list, bounded grup listesi ve rol allow-list'i.
- İdempotent subject link'i ve login takeover koruması.
- Status komutu ve production-style transaction rollback testi.

## Sonraki kapı

`SEC-03b`, gerçek OIDC Authorization Code + PKCE adaptörü, JWKS rotation/cache, nonce/state/replay koruması, SCIM 2.0 User/Group provisioning, deprovisioning ve tenant membership reconciliation ekleyecektir. Bu tamamlanmadan ürün “SSO/SCIM hazır” olarak pazarlanmaz.
