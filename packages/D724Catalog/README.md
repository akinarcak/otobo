# D724Catalog

GPL-3.0 tenant-safe service portfolio and catalog repository for D724 ESM.

The package provides scoped create, read, list, and optimistic update operations
for services, service offerings, and requestable catalog items. Every database
query includes `tenant_id`; cross-tenant parent relationships are rejected; and
authorization is delegated to `D724TenantGuard` before data access.

Run `bin/otobo.Console.pl Admin::D724::CatalogStatus --json` after installation
to verify configuration and schema health.
