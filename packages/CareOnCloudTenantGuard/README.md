# CareOnCloudTenantGuard

`CareOnCloudTenantGuard` provides the default-deny authorization primitive for all tenant-owned CareOnCloud resources. Version `0.1.1` depends on `CareOnCloudFoundation >= 0.1.0`.

The package does not automatically make every CareOnCloud ESM screen multi-tenant. Each data adapter must call the guard before reading or mutating a resource and must start searches from `ScopeGet()`. See `docs/esm/security/TENANT-THREAT-MODEL.md` for required integration gates.

## Diagnostic example

```bash
bin/careoncloud.Console.pl Admin::CareOnCloud::TenantGuardCheck \
  --subject-id agent-1 \
  --subject-tenant tenant-a \
  --role agent \
  --resource-tenant tenant-a \
  --action case.update \
  --json
```

An allowed decision exits `0`; a denied decision exits non-zero and contains a stable reason code suitable for audit events.
