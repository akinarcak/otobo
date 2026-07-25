# SEC-03 Birleşik Kimlik Güven Sınırı

`D724Identity`, CareOnCloud ESM'in OIDC/SAML ve sonraki SCIM adaptörleri için tenant-safe çekirdek sözleşmesidir. Sürüm 0.2.0, OTOBO'nun yerleşik JWKS/imza doğrulayıcısını kullanan Authorization Code akış güvenlik katmanını da içerir.

## Değişmezler

- Tenant hiçbir zaman token içindeki serbest `tenant_id` claim'inden seçilmez.
- Tenant, veritabanında benzersiz olan exact `(issuer, audience)` trust route'undan türetilir.
- Yalnız HTTPS issuer kabul edilir; query/fragment ve wildcard issuer yasaktır.
- E-posta domain'i provider allow-list'inde olmalıdır.
- Grup→rol eşlemesi yalnız bilinen tenant rollerine yapılabilir; eşleşmeyen gruplar yetki kazandırmaz.
- Her kimlik varsayılan `requester` rolüyle başlar.
- `(provider, subject)` bağı değişmezdir. Subject farklı login'e, aynı tenant login'i farklı subject'e bağlanamaz.
- Provider oluşturma ve ilk subject link'i audit olayıyla aynı transaction'dadır.
- Authorization isteği state, nonce ve PKCE verifier için kriptografik rastgele değerler üretir; veritabanında yalnız SHA-256 özetleri saklanır.
- Callback, state satırını transaction içinde kilitler; browser binding, PKCE S256, exact issuer/audience ve nonce doğrulamasından sonra akışı tek kullanımlık olarak tüketir.
- Dönüş hedefi yalnız yerel `/otobo/...` yoludur. Open redirect kabul edilmez.
- Discovery metadata issuer ile aynı HTTPS origin'den authorization, token ve JWKS endpoint'i vermeli; ID token algoritması yalnız `RS256` veya `ES256` olabilir.

## Tamamlanan kapsam

- Tenant-admin korumalı provider trust route oluşturma.
- OIDC/SAML verifier sonucu için fail-closed claim çözümleme.
- Domain allow-list, bounded grup listesi ve rol allow-list'i.
- İdempotent subject link'i ve login takeover koruması.
- Status komutu ve production-style transaction rollback testi.
- Authorization Code başlangıç sözleşmesi, PKCE S256, metadata güven sınırı, OTOBO JWKS doğrulayıcı delegasyonu ve replay engeli.

## Sonraki kapı

`SEC-03b-web`, bu çekirdeği agent/customer login ve callback controller'larına bağlayacak; gerçek bir dış IdP ile uçtan uca kabul ve logout/session politikası ekleyecektir. `SEC-03c`, SCIM 2.0 User/Group provisioning, deprovisioning ve tenant membership reconciliation ekleyecektir. Bunlar tamamlanmadan ürün “SSO/SCIM hazır” olarak pazarlanmaz.
