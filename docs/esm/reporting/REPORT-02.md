# REPORT-02 — Operations Center

Status: implemented in `CareOnCloudReporting` 0.3.1.

`AgentCareOnCloudOperations` is the management-facing, tenant-scoped operational dashboard. It reuses the same privacy-minimized `Reporting::Summary` contract as CSV/JSON export and shows request totals, SLA objectives, breaches, calculated compliance, request status, demand by catalog item and SLA health for a validated date range.

The screen only offers tenants for which the authenticated subject has `report.read`. A requested tenant is intersected with that set before any query. Tenant display labels require the same authorization, report cache keys remain tenant-bound, and ordinary agents without a service-owner, auditor or tenant-admin role fail closed.
