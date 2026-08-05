# CHANGE-01 — Change Enablement core

Status: backend and agent/CAB workbench implemented in `CareOnCloudChange` 0.2.1.

The tenant-safe change repository provides numbered change records, standard/normal/emergency types, deterministic impact × likelihood risk scoring, mandatory implementation/test/backout plans, optional tenant-bound service-instance impact, optimistic locking and an auditable lifecycle.

Low/medium risk changes move from `draft` to `scheduled`; high/critical changes enter `awaiting_approval`. CAB decisions require the service-owner/tenant-admin management permission. Execution is restricted to `scheduled → implementing → completed|failed`, with cancellation from scheduled. Every successful mutation is written to the tenant audit chain in the same database transaction.
