# CMDB-01 — Service context and configuration graph

Status: implemented in `D724CMDB` 0.1.2.

## Product model

CareOnCloud uses the following service-context chain:

`Service Category → Service → Service Instance → Configuration Item`

- A Service Category groups portfolio services.
- A Service remains the tenant-owned catalog service from `D724Catalog`.
- A Service Instance represents the concrete, customer-specific delivery of a service. Its support team, commercial service model, lifecycle state, and criticality are fields of that instance.
- Configuration Items have tenant-defined types and validated attribute schemas.
- Service Instances bind to CIs; CIs form a bounded directed graph.

This distinction is intentional: support team is not a hierarchy level, and preventive maintenance is a request/task category rather than a parallel catalog branch.

## Repository boundary

The package owns seven tables: service categories, service-category assignments, service instances, CI types, CIs, CI relations, and service-instance/CI bindings. Every parent relation carries `tenant_id` and is protected by a composite foreign key. The application layer also authorizes every operation through `D724TenantGuard`.

Mutations require an agent `UserID`, emit normalized tamper-evident audit events, and use optimistic versions for updates and retirement. Dependency relations reject cycles and graph traversal is limited to 500 nodes.

## Workbook interpretation

Source reviewed: `Careon_4me_Kirilim_Yapisi_4.xlsx`.

- 51 mapped services and 831 customer/service mappings were found.
- 43 customers have mappings; the customer sheet contains 46 customer rows.
- `Kırılım 1` maps to Service Category.
- `Kırılım 3` maps to Service.
- `Kırılım 2 / Support Team` maps to Service Instance support team.
- `Sabit Kapsam (Teklif Bazlı)` maps to `fixed_scope`.
- `Unify Pack (Ticket Bazlı, Tüm Katalog)` maps to `unify_pack`.
- Vendor or technology variants such as Windows/Linux, AD DS/Entra, VMware/Hyper-V, and backup/security products become separate Service Instances where delivery ownership differs.

The workbook's review sheet contains 15 unresolved or out-of-catalog mappings. These must remain import warnings until a catalog owner classifies them; the importer must not silently invent portfolio structure.

Customer and brand names in the workbook are reference/demo inputs only. Their presence must not be presented as evidence that those organizations use CareOnCloud.

## Authorization

- `tenant_admin`: `cmdb.read`, `cmdb.manage`
- `agent`, `service_owner`, `auditor`, `automation`: `cmdb.read`
- `requester`: no CMDB access in the initial policy

The default-deny policy version is 1.8.0.

## Verification

- `D724/CMDB.t`: category, service instance, schema validation, CI lifecycle, binding, graph, audit, concurrency, tenant isolation, and cycle rejection.
- `D724/CMDBConstraint.t`: all eight composite tenant constraints and a direct cross-tenant database attack.
- `Admin::D724::CMDBStatus --json`: package state, seven tables, and constraint health.
