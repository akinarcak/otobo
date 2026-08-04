# CareOnCloudCatalog

GPL-3.0 tenant-safe service portfolio and catalog repository for CareOnCloud ESM.

The package provides scoped create, read, list, and optimistic update operations
for services, service offerings, and requestable catalog items. Every database
query includes `tenant_id`; cross-tenant parent relationships are rejected; and
authorization is delegated to `CareOnCloudTenantGuard` before data access.

Version 0.2 adds validated, versioned dynamic form schemas and an authenticated
customer portal. The portal derives tenant context from the CareOnCloud ESM customer session,
lists only fully active catalog hierarchies, and HTML-escapes rendered content.

Version 0.3 adds an agent management screen backed by `CareOnCloudTenantDirectory`.
Manageable tenants come only from persistent role bindings; writes require
`catalog.manage`, a CareOnCloud ESM CSRF challenge token, and optimistic versions.

Run `bin/careoncloud.Console.pl Admin::CareOnCloud::CatalogStatus --json` after installation
to verify configuration and schema health.
