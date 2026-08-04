# ADR-001 - Canonical API mount in the CareOnCloud ESM fork

- Status: accepted
- Date: 2026-07-24
- Decision owners: CareOnCloud ESM maintainers

## Context

CareOnCloud ESM exposes package-friendly Public frontend modules, but it does not provide
a package registration point for a new top-level PSGI mount. Publishing only a
`public.pl?Action=...` URL would expose implementation details and prevent a
stable resource-oriented `/api/v1` contract.

## Decision

The fork adds one routing adapter in `bin/psgi-bin/careoncloud.psgi`. The adapter maps
only these exact paths to the package-owned `PublicCareOnCloudAPI` module:

- `/api/v1/oauth/token`
- `/api/v1/tickets` and `/api/v1/tickets/{positive_integer}`
- `/api/v1/requests` and `/api/v1/requests/{positive_integer}`
- `/api/v1/openapi.json`

Authentication, validation, authorization, rate limiting, serialization, and
domain behavior remain in the independently versioned GPL-3.0 `CareOnCloudAPI` package.
Unknown paths map to a JSON `404`. The existing Public-interface availability,
HTTPS redirect, performance logging, object lifecycle, exception, and request
size middleware remain in force.

`Admin::CareOnCloud::APIStatus` fails closed unless both the canonical mount and the
parseable OpenAPI 3.1 artifact are installed. This prevents a package-only
upgrade from being reported healthy when the fork routing adapter is absent.

## Consequences

- Product deployments must build the web image from this fork; installing the
  package into an arbitrary upstream CareOnCloud ESM image is insufficient.
- Upstream rebases must review this single mount block explicitly.
- The compatibility `public.pl` route remains available for rollback, but it is
  not the advertised integration contract.
- Existing persistent application volumes need the normal core update step and
  a web worker restart; package upgrade alone cannot introduce the mount.

## Rejected alternatives

- Rewriting at an external reverse proxy was rejected as the only mechanism
  because local development and self-hosted installs would have divergent APIs.
- Shipping the complete upstream `careoncloud.psgi` inside an OPM was rejected because
  package ownership of a core file would make upstream upgrades unsafe.
- A second standalone API process was deferred until scale or isolation evidence
  justifies the operational cost.
