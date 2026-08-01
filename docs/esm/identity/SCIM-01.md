# SCIM-01 - Tenant-isolated provisioning

CareOnCloud ESM exposes SCIM 2.0 at `/careoncloud/scim/v2`. Every request requires:

- `Authorization: Bearer <64-character tenant-bound API token>`
- `X-CareOnCloud-Tenant: <tenant key>`
- an API client with the `tenant_admin` role, which is the only role granted
  the `scim.provision` policy action

The API client is created and rotated by the existing D724 API client tooling.
SCIM does not introduce a second secret store. Client secrets are bcrypt
protected, access tokens are stored only as SHA-256 digests, and tokens cannot
be used against another tenant.

## Resources

- `GET|POST /Users`, `GET|PUT|PATCH|DELETE /Users/{id}`
- `GET|POST /Groups`, `GET|PUT|PATCH|DELETE /Groups/{id}`
- `GET /ServiceProviderConfig`, `/Schemas`, `/ResourceTypes`

Writes return weak ETags and require `If-Match: W/"<version>"` after resource
creation. `userName` and `externalId` are immutable so a directory update
cannot take over an existing native login. Lists accept only bounded equality
filters for `id`, `userName`/`displayName`, and `externalId`, with a maximum
page size of 200.

The CareOnCloud extension selects `agent` or `customer` account surfaces and
maps a SCIM group to one allow-listed tenant role. Deprovisioning revokes all
roles in the target tenant. A native agent remains active when another tenant
still has an active membership. Reactivation restores the requester baseline
and every role derived from current SCIM group membership.

All mutations and their `integration:<client id>` audit events share one
database transaction. Unknown tenant-local resources return `404`; a token
used with a different tenant returns `403`.
