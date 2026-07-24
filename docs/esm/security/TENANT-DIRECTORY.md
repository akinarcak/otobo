# Tenant Directory and Role Bindings

`D724TenantDirectory` is the authoritative mapping between OTOBO agent IDs and D724 tenants. It replaces configuration-based or request-provided tenant selection with persistent, audited memberships.

## Authorization model

- An agent may have multiple roles in multiple tenants.
- Roles are represented as `RoleBindings => { tenant_id => [roles...] }`; they are never flattened into one global role list.
- TenantGuard selects roles only for the resource tenant. A `tenant_admin` role in tenant A cannot grant `catalog.manage` or `tenant.manage` in tenant B.
- Active context includes only active memberships joined to active tenants.
- `platform_admin` is not a tenant-grantable role. Its emergency cross-tenant bypass remains disabled by default in TenantGuard configuration.
- Membership changes require an authenticated directory-derived subject with `tenant.manage` in the target tenant.
- The last active tenant administrator cannot revoke its own final administrator binding.
- Membership mutations lock the tenant row before reading administrator counts, so concurrent revocations serialize on one tenant boundary.
- Tenant and membership mutations append normalized audit events in the same database transaction; an audit failure rolls the domain mutation back.
- Membership grant/revoke is versioned and idempotent. A replay does not create another audit sequence or advance the membership version.
- A tenant administrator cannot suspend or retire its tenant; that requires explicitly enabled and auditable platform administration.

## Bootstrap

`Admin::D724::TenantBootstrap` works only while the directory contains zero tenants and requires `--confirm-bootstrap`. It creates the first tenant and one `tenant_admin` membership for an existing OTOBO agent. Later grants use `Admin::D724::TenantMembershipGrant`, which derives and checks the actor context before writing.

## Transaction and audit evidence

`D724TenantDirectory 0.2.1` uses production-style transactions and a tenant-row `FOR UPDATE` lock. The package test suite injects audit failure into real grant and revoke calls: failed grants leave no membership row, failed revokes preserve `active/version=1`, and successful retries produce exactly one grant and one revoke event in a valid tenant hash chain. A clustered multi-process last-admin race acceptance test remains a release-hardening item even though the repository locking invariant is implemented.
