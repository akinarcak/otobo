# CAT-02a Customer Catalog Portal

## Delivered contract

- The authenticated CareOnCloud ESM customer company ID is the tenant boundary for the portal request.
- The browser cannot select or override `TenantID`; `CustomerCareOnCloudCatalog` derives it from the authenticated session.
- Customer login identifiers are SHA-256 normalized before becoming TenantGuard subject identifiers, so email-style logins remain valid without exposing them in policy decisions.
- Only active services, offerings, and catalog items are listed.
- Customers explicitly select a service category, service extension, and request type before the dynamic request form opens.
- The selected hierarchy is validated server-side; a catalog item cannot be submitted with a mismatched service or extension identifier.
- Item detail is unavailable if any parent in its hierarchy is not active.
- Form schemas support `text`, `textarea`, `select`, `multiselect`, `checkbox`, `date`, `datetime`, `number`, and `email` fields.
- Schema keys, labels, required flags, option values, sizes, and field counts are validated server-side. Script/HTML field types and duplicate keys/options are rejected.
- Schema writes use optimistic versioning and all reads/writes are tenant scoped.
- CareOnCloud ESM Template Toolkit HTML filters escape catalog and schema content before rendering.

## Submission boundary

`CareOnCloudRequest` owns CSRF validation, server-side answer validation, idempotency, audit events, commitments and workflow routing. `CareOnCloudCatalog` owns the tenant-safe three-level selection and dynamic form definition. The submitted service and extension identifiers are checked against the selected catalog item before request orchestration starts.

## Test-server evidence

`CareOnCloudCatalog 0.2.4` was upgraded from the installed 0.1/0.2 lineage, including the new schema table. Package tests cover repository isolation, form validation, parent availability, immutable hierarchy links, HTML escaping, and template rendering. An authenticated demo customer session rendered both the catalog overview and dynamic form detail over HTTP on the private test endpoint.
