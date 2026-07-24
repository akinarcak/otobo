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
- A tenant administrator cannot suspend or retire its tenant; that requires explicitly enabled and auditable platform administration.

## Bootstrap

`Admin::D724::TenantBootstrap` works only while the directory contains zero tenants and requires `--confirm-bootstrap`. It creates the first tenant and one `tenant_admin` membership for an existing OTOBO agent. Later grants use `Admin::D724::TenantMembershipGrant`, which derives and checks the actor context before writing.

## Remaining hardening

The last-admin check is enforced in the repository. Before a clustered production release, membership mutation must also use a database transaction/locking strategy so two concurrent revocations cannot race. This is tracked as a release security gate rather than being represented as already solved.
