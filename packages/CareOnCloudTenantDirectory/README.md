# CareOnCloudTenantDirectory

GPL-3.0 persistent tenant and tenant-bound OTOBO agent role directory for CareOnCloud ESM.

The package resolves trusted TenantGuard subjects with per-tenant `RoleBindings`,
provides one-time bootstrap and audited membership grant commands, and prevents
common administration lockouts. See `docs/esm/security/TENANT-DIRECTORY.md` for
the security contract and remaining clustered-release hardening gate.
