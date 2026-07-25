# API-01 - Tenant-safe integration API

## Implemented contract (`D724API 0.7.1`)

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
Token issue and individual revoke append `api.token.issued` and
`api.token.revoked`; audit details contain only a short digest fingerprint,
never the bearer token or its complete stored digest.

### Secret rotation

Tenant administrators rotate a client with the console command below. The
current optimistic version is mandatory, and `--confirm` makes the disruptive
token invalidation explicit:

```text
bin/otobo.Console.pl Admin::D724::APIClientRotate \
  --tenant-id TENANT --client-id CLIENT --expected-version VERSION \
  --actor-user-id USER_ID --confirm
```

The new secret is printed exactly once. Secret hash replacement, client version
advance, revocation of every active token, and `api.client.secret_rotated` audit
append share one database transaction. An audit or concurrent-version failure
rolls all four effects back. The old secret and old tokens become invalid as
soon as a successful rotation commits.

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

### Approval and fulfillment lifecycle writes

- `POST /otobo/api/v1/requests/{request_id}/approval`
- `PATCH /otobo/api/v1/tasks/{task_id}`

Approval bodies require `decision` (`approved` or `rejected`) and
`expected_version`; task bodies require `status` (`in_progress`, `completed`,
or `failed`) and `expected_version`. Both accept an optional comment of at most
4,000 characters. Optimistic version checks and the existing transition state
machine remain authoritative.

The token role must pass `case.update`; an approval additionally requires the
role configured on the pending approval. Consequently, a requester integration
cannot approve a tenant-admin step even when it knows the request ID. The
token-derived `integration:<client-id>` subject is validated as single-tenant,
passed through `D724TenantGuard`, reused by commitment synchronization, and
recorded as actor type `integration`. No synthetic agent ID or audit-free
mutation path exists.

Repeating the exact approval or task transition with its original expected
version returns `200` and `Idempotent-Replayed: true` without another mutation
or audit append. A stale version with a different target returns `409`.

### Lifecycle webhook subscriptions

- `GET|POST /otobo/api/v1/webhook-subscriptions`
- `GET|PATCH /otobo/api/v1/webhook-subscriptions/{subscription_id}`

Only a role passing `tenant.manage` can administer subscriptions. The bearer
token tenant is authoritative and every get/list/update predicate includes it.
Create accepts a deployment-configured `endpoint_key`, a stable key/name,
exact or prefix-wildcard event patterns, and an optional audit start cursor.
Arbitrary URLs and secrets are never accepted by the API. Update requires
`expected_version`; stale writes return `409`. Full delivery semantics and
receiver verification are specified in `WEBHOOK-01.md`.

## Security invariants

- Default-deny `D724TenantGuard` authorization runs before rate consumption and data access.
- Client identity, role, rate limit, TTL, and token are bound to exactly one active tenant.
- SQL values use bind parameters; limits and cursors are range/format validated before query execution.
- List filtering occurs in SQL, not as an application post-filter.
- Cross-tenant denial does not reveal whether the requested ticket exists.
- Acceptance tooling never prints client secrets or bearer tokens.
- Canonical path-derived `Action` and `Route` values take precedence over query-string injection attempts.
- Request JSON bodies are capped at 64 KiB and reject unsupported media types.
- Token issue/revoke and client create/rotate/revoke are transaction-audited without secret material.
- Lifecycle writes reuse the request transaction boundary, normalized audit chain, commitment synchronization, role check, and tenant guard.

## Retention and operational metrics

`Admin::D724::APIStatus --json` reports active/revoked/expired clients and
tokens, current-minute request volume, total/stale rate and metric windows,
five-minute request/error counts, route series, average/maximum latency, stale
token digests, invalid hashes/tenant references, retention validity, canonical
mount, and OpenAPI health. Any query error or structural invariant failure
makes the command fail closed.

Every public request records one atomic minute aggregate after response
creation. Dimensions are limited to tenant (or the reserved `__public__`
authentication boundary), a fixed route key, normalized method, status and
bounded error code. Raw paths, ticket/request IDs, tokens and client IDs cannot
become labels. The upsert accumulates request count, duration sum and maximum,
so multiple web workers do not lose increments. Defaults warn at 2,000 ms
maximum latency or 5% server-error rate after at least 20 requests.

Defaults retain expired/revoked token digests for 30 days, rate windows for 48
hours, and API metric windows for 168 hours. A scheduler may run this confirmed
maintenance command daily:

```text
bin/otobo.Console.pl Maint::D724::APIRetentionCleanup --confirm
```

Only expired or revoked token digests and completed rate windows older than the
configured thresholds are deleted. Client records and immutable audit evidence
are retained.

## Verified acceptance (`2026-07-25`)

`development/d724/Accept-API.pl` created a short-lived requester client for
`d724-demo`, exercised the real HTTP endpoint, and revoked the client. Evidence:

- token `200`, list `200`, same-tenant get `200`;
- unknown/cross-scope get `404`;
- every listed object had `tenant_id=d724-demo`;
- the same token returned `401` immediately after client revocation;
- canonical OpenAPI returned `200` and parsed as version `3.1.0`;
- request create/replay/conflict/get returned `201/200/409/200` for request `187`;
- rotation advanced version to `2`; old token/secret returned `401/401`, while
  the new secret/token returned `200/200`;
- `Accept-APILifecycle.pl` created request `203`; requester approval was `403`,
  tenant-admin approval/replay was `200/200`, task start/replay/complete was
  `200/200/200`, and the final requester-owned GET returned `fulfilled`;
- exactly four lifecycle audit events retained actor type `integration`, while
  approval and task replays appended no duplicates;
- `Accept-WebhookSubscription.pl` returned requester/tanimsiz-endpoint/create/
  list/get/disable/stale statuses `403/422/201/200/200/200/409`; audit sequence
  `116` became shared outbox delivery `74` exactly once;
- `Accept-APIMetrics.pl` recorded three successful ticket reads, a normalized
  unknown route and an invalid credential as tenant `tickets/200`, tenant
  `not_found/404`, and `__public__/tickets/401`; no raw/high-cardinality route
  label was stored;
- `Accept-APIMetricConcurrency.pl` ran 12 independent database writers against
  one minute series and obtained exactly one row with count/sum/max `12/78/12`;
- all 39 D724 test files and 799 assertions passed together.

## Remaining API-01 work

External metric export/dashboard delivery and sustained capacity testing remain
open. Route latency/error aggregation, retention cleanup, webhook backlog
health, bounded-cardinality checks and concurrent writer acceptance are
complete. The lifecycle subscription, canonical JSON/HMAC delivery, and
dead-letter replay contracts are complete in `WEBHOOK-01`.
Until TLS termination is deployed, this test endpoint must stay on the private
network and must not be exposed to the public Internet.
