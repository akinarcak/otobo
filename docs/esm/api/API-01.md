# API-01 - Tenant-safe integration API

## Implemented contract (`D724API 0.3.0`)

The API is a GPL-3.0 package and uses OTOBO's supported public frontend
registration. Its canonical versioned base URL is:

`/otobo/api/v1`

The legacy compatibility transport remains available at:

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

`POST /otobo/api/v1/oauth/token`

Content type is `application/x-www-form-urlencoded`; required fields are
`grant_type=client_credentials`, `client_id`, and `client_secret`. A successful
response contains `access_token`, `token_type=Bearer`, `expires_in`, `tenant_id`,
and the tenant-bound role. Client secrets use bcrypt at rest. Bearer tokens are
opaque 64-character random values; only their SHA-256 digest is stored.

Clients are created by a tenant administrator. `ClientRevoke` atomically changes
the optimistic client version, revokes every active token, and appends
`api.client.revoked` to the tenant audit chain. Revocation replay is idempotent.

### Ticket reads

- `GET /otobo/api/v1/tickets?limit=50&after_id=0`
- `GET /otobo/api/v1/tickets/9`

The bearer token's tenant is the sole tenant selector; the caller cannot supply
or override it. Reads join the immutable `d724_ticket_scope` predicate before
returning data. The projection is deliberately small: ID, number, title, queue,
state, priority, tenant ID, and timestamps. Article bodies and other PII are not
part of this contract. Pagination is stable by ticket ID, with a maximum page of
100 and an opaque-use `next_cursor` value.

An unknown ticket and a ticket in another tenant both return `404 NOT_FOUND`.
Role denial is `403`, invalid/expired/revoked credentials are `401`, and the
atomic per-client minute limit returns `429` with `Retry-After: 60`.

### Idempotent service-request writes

`POST /otobo/api/v1/requests` requires `Content-Type: application/json`, a
16-128 character `Idempotency-Key` header, and this body shape:

```json
{
  "catalog_item_id": 1,
  "requester_login": "demo.customer",
  "answers": {"employee":"Example","device_profile":"standard","justification":"Replacement"}
}
```

The requester must be an active customer account whose `UserCustomerID` exactly
matches the token tenant. The API delegates to the existing transaction-atomic
request/catalog/form/workflow/audit implementation. First creation returns
`201`; an identical replay returns the original request with `200` and
`Idempotent-Replayed: true`; reuse with a different payload returns `409`.

`GET /otobo/api/v1/requests/{id}?requester_login=...` returns only a request
owned by that validated requester. The API projection excludes submitted answer
values and workflow internals to avoid unnecessary PII disclosure.

The machine-readable contract is public at
`GET /otobo/api/v1/openapi.json` with media type
`application/vnd.oai.openapi+json;version=3.1`.

## Security invariants

- Default-deny `D724TenantGuard` authorization runs before rate consumption and data access.
- Client identity, role, rate limit, TTL, and token are bound to exactly one active tenant.
- SQL values use bind parameters; limits and cursors are range/format validated before query execution.
- List filtering occurs in SQL, not as an application post-filter.
- Cross-tenant denial does not reveal whether the requested ticket exists.
- Acceptance tooling never prints client secrets or bearer tokens.
- Canonical path-derived `Action` and `Route` values take precedence over query-string injection attempts.
- Request JSON bodies are capped at 64 KiB and reject unsupported media types.

## Verified acceptance (`2026-07-24`)

`development/d724/Accept-API.pl` created a short-lived requester client for
`d724-demo`, exercised the real HTTP endpoint, and revoked the client. Evidence:

- token `200`, list `200`, same-tenant get `200`;
- unknown/cross-scope get `404`;
- every listed object had `tenant_id=d724-demo`;
- the same token returned `401` immediately after client revocation;
- canonical OpenAPI returned `200` and parsed as version `3.1.0`;
- request create/replay/conflict/get returned `201/200/409/200` for request `187`;
- all 30 D724 test files and 580 assertions passed together.

## Remaining API-01 work

Client secret rotation, write endpoints for lifecycle transitions, signed
outbound webhook contract, retention for revoked clients/tokens/rate windows,
API metrics, and concurrent load tests remain open.
Until TLS termination is deployed, this test endpoint must stay on the private
network and must not be exposed to the public Internet.
