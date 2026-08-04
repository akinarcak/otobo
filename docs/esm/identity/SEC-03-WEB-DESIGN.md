# SEC-03b-web OIDC Giriş Adapter'i

## Amaç

CareOnCloud agent ve müşteri girişlerini tenant'a bağlı OIDC Authorization Code +
PKCE akışına bağlamak; mevcut CareOnCloud ESM DB parola girişini kesmeden kademeli SSO
geçişi sağlamak.

## CareOnCloud ESM entegrasyon kararı

`Kernel::System::Auth::D724OpenIDConnect` ve
`Kernel::System::CustomerAuth::D724OpenIDConnect` birincil auth backend olarak
çalışır. Sıradan kullanıcı/parola isteğini mevcut `DB` backend'ine delegeler.
`PreAuth` yalnız istek geçerli `TenantID + ProviderKey` seçimi taşıyorsa veya bir
CareOnCloud OIDC callback state'i varsa etkin olur. Böylece SSO yapılandırılmamış
tenant'lar ve demo hesapları mevcut parola ekranını kullanmaya devam eder.

## Provider yapılandırması

- Trust route kaynağı `d724_identity_provider` tablosudur.
- Client secret yeni bir CareOnCloud tablosuna kopyalanmaz. CareOnCloud ESM'nun mevcut
  `oidc_profiles` deposundaki `careoncloud:<tenant>:<provider>:<surface>` adlı profil kullanılır.
- Profil `client_id` değeri trust route `audience` değeriyle exact eşleşmelidir.
- Discovery sonucu `OIDCFlow::MetadataValidate` güven sınırından geçmeden redirect
  veya token isteği yapılmaz.
- Redirect URI, agent ve customer yüzeyi için önceden tanımlı HTTPS URL olmalıdır;
  callback parametresinden türetilmez.

## Başlangıç akışı

1. `TenantID`, `ProviderKey`, yüzey ve yerel dönüş yolu bounded allow-list ile doğrulanır.
2. 32 byte browser binding üretilir.
3. `OIDCFlow::Begin` kriptografik state, nonce ve verifier üretir; sunucuda yalnız
   özetlerini saklar.
4. Browser binding ve verifier, state'e özel `Secure; HttpOnly; SameSite=Lax`
   cookie'de en fazla 300 saniye tutulur.
5. Authorization URL `response_type=code`, exact redirect URI, nonce,
   `code_challenge` ve `code_challenge_method=S256` ile oluşturulur.

## Callback akışı

1. Provider hataları bounded ve PII içermeyen log olayına çevrilir.
2. State'e özel cookie okunur; eksik/bozuk cookie'de token endpoint çağrılmaz.
3. Pending flow context state, browser binding ve verifier özetleriyle bulunur.
4. Yalnız bu context'in tenant/provider profilinden token endpoint belirlenir.
5. Authorization code exact verifier ile değiştirilir; ID token ham olarak loglanmaz.
6. `OIDCFlow::CallbackVerify` JWKS/imza, exact issuer/audience, nonce, browser binding,
   PKCE ve replay kontrollerini transaction içinde tamamlar.
7. Dönen login ilgili CareOnCloud ESM agent/customer deposunda aktif ve aynı tenant'ta önceden
   provision edilmiş olmalıdır. Otomatik kullanıcı/rol provision etme SCIM kapısına
   kadar yapılmaz.
8. Başarı veya hata sonunda state cookie silinir. Başarıda yalnız flow tablosundaki
   doğrulanmış yerel dönüş yolu kullanılır.

## Güvenlik değişmezleri

- Tenant hiçbir browser cookie, callback query veya token `tenant_id` claim'inden
  seçilmez; kalıcı trust route'tan gelir.
- Callback state tek kullanımlıktır ve satır kilidi altında tüketilir.
- Client secret, code, verifier ve ID token log/audit detayına yazılmaz.
- Unknown tenant/provider dışarıda aynı genel hata mesajını üretir.
- Provider profile mismatch, cross-origin metadata, `plain` PKCE, açık redirect,
  eksik cookie, wrong surface ve inactive user fail-closed sonuçlanır.
- Agent ve customer callback'leri birbirinin cookie/redirect/surface bağını kabul etmez.

## Kabul kapıları

- DB parola agent ve customer girişleri değişmeden çalışır.
- Agent/customer OIDC başlangıcında URL'de exact S256 challenge bulunur.
- Wrong browser, verifier, nonce, issuer, audience, tenant, surface ve replay negatif
  testleri geçer.
- Mock IdP ile authorization-code/token/JWKS uçtan uca HTTP kabulü geçer.
- Gerçek dış IdP kabulü yapılmadan ürün “SSO hazır” olarak pazarlanmaz.
