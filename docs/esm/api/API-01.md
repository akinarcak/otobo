# API-01 - Tenant-safe integration API

## Implemented contract (`D724API 0.2.3`)

The first API slice is a GPL-3.0 package and uses OTOBO's supported public
frontend registration. The compatibility transport base URL is:

`/otobo/public.pl?Action=PublicD724API`

All responses are JSON, carry `Cache-Control: no-store` and
`X-Content-Type-Options: nosniff`, and use a stable envelope:

```json
{"success":true,"data":{},"meta":{}}
```

Errors do not include stack traces, SQL details, client secrets, token digests,
or cross-tenant object existence:

```json
{"success":false,"error":{"code":"NOT_FOUND"}}
```

### Client credentials

`POST ?Action=PublicD724API&Route=token`

Content type is `application/x-www-form-urlencoded`; required fields are
`grant_type=client_credentials`, `client_id`, and `client_secret`. A successful
response contains `access_token`, `token_type=Bearer`, `expires_in`, `tenant_id`,
and the tenant-bound role. Client secrets use bcrypt at rest. Bearer tokens are
opaque 64-character random values; only their SHA-256 digest is stored.

Clients are created by a tenant administrator. `ClientRevoke` atomically changes
the optimistic client version, revokes every active token, and appends
`api.client.revoked` to the tenant audit chain. Revocation replay is idempotent.

### Read cases

- `GET ?Action=PublicD724API&Route=tickets&limit=50&after_id=0`
- `GET ?Action=PublicD724API&Route=ticket&ticket_id=9`

The bearer token's tenant is the sole tenant selector; the caller cannot supply
or override it. Reads join the immutable `d724_ticket_scope` predicate before
returning data. The projection is deliberately small: ID, number, title, queue,
state, priority, tenant ID, and timestamps. Article bodies and other PII are not
part of this contract. Pagination is stable by ticket ID, with a maximum page of
100 and an opaque-use `next_cursor` value.

An unknown ticket and a ticket in another tenant both return `404 NOT_FOUND`.
Role denial is `403`, invalid/expired/revoked credentials are `401`, and the
atomic per-client minute limit returns `429` with `Retry-After: 60`.

## Security invariants

- Default-deny `D724TenantGuard` authorization runs before rate consumption and data access.
- Client identity, role, rate limit, TTL, and token are bound to exactly one active tenant.
- SQL values use bind parameters; limits and cursors are range/format validated before query execution.
- List filtering occurs in SQL, not as an application post-filter.
- Cross-tenant denial does not reveal whether the requested ticket exists.
- Acceptance tooling never prints client secrets or bearer tokens.

## Verified acceptance (`2026-07-24`)

`development/d724/Accept-API.pl` created a short-lived requester client for
`d724-demo`, exercised the real HTTP endpoint, and revoked the client. Evidence:

- token `200`, list `200`, same-tenant get `200`;
- unknown/cross-scope get `404`;
- every listed object had `tenant_id=d724-demo`;
- the same token returned `401` immediately after client revocation;
- all 29 D724 test files and 562 assertions passed together.

## Remaining API-01 work

The canonical `/api/v1` path, OpenAPI document, write endpoints with idempotency
keys, client secret rotation, signed outbound webhook contract, retention for
revoked clients/tokens/rate windows, and concurrent load tests remain open.
Until TLS termination is deployed, this test endpoint must stay on the private
network and must not be exposed to the public Internet.
