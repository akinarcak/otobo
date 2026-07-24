# CAT-02a Customer Catalog Portal

## Delivered contract

- The authenticated OTOBO customer company ID is the tenant boundary for the portal request.
- The browser cannot select or override `TenantID`; `CustomerD724Catalog` derives it from the authenticated session.
- Customer login identifiers are SHA-256 normalized before becoming TenantGuard subject identifiers, so email-style logins remain valid without exposing them in policy decisions.
- Only active services, offerings, and catalog items are listed.
- Item detail is unavailable if any parent in its hierarchy is not active.
- Form schemas support `text`, `textarea`, `select`, `multiselect`, `checkbox`, `date`, `datetime`, `number`, and `email` fields.
- Schema keys, labels, required flags, option values, sizes, and field counts are validated server-side. Script/HTML field types and duplicate keys/options are rejected.
- Schema writes use optimistic versioning and all reads/writes are tenant scoped.
- OTOBO Template Toolkit HTML filters escape catalog and schema content before rendering.

## Deliberate boundary

The rendered form is read-only in CAT-02a. Submission and ticket/fulfillment creation belong to `FLOW-01`, where CSRF protection, server-side answer validation, idempotency, audit events, and workflow routing will be implemented together. A tenant-admin catalog management screen remains `CAT-02b`; catalog management is currently available through the guarded repository API.

## Test-server evidence

`D724Catalog 0.2.4` was upgraded from the installed 0.1/0.2 lineage, including the new schema table. Package tests cover repository isolation, form validation, parent availability, immutable hierarchy links, HTML escaping, and template rendering. An authenticated demo customer session rendered both the catalog overview and dynamic form detail over HTTP on the private test endpoint.
