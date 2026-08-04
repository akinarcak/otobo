# PROBLEM-01 — Problem Management core

Status: backend and agent Problem/RCA workbench implemented in `CareOnCloudProblem` 0.2.0.

The tenant-safe problem repository provides numbered records, deterministic impact/urgency priority, investigation, root-cause analysis, workaround publication, known-error lifecycle, permanent-fix evidence, management-controlled closure and reopen, optimistic locking, transactional audit and cross-tenant denial.

The workflow is `draft → investigating → known_error|resolved → closed`. A known error cannot be published without both root cause and workaround; resolution requires root cause and a permanent fix. Closing or reopening requires the service-owner/tenant-admin management permission. Every versioned state transition locks the tenant-scoped Problem row with `FOR UPDATE` inside the domain/audit transaction, so concurrent writers cannot both pass the optimistic-version check.

Verification note (2026-08-02): the package regression includes audit-failure rollback coverage for Problem creation. Candidate runtime execution was attempted, but `careoncloud_problem` is absent because the candidate package has not been installed through its `DatabaseInstall` manifest. Runtime acceptance remains pending a reproducible OPM build/install/upgrade gate; source-file copying is not accepted as package installation evidence.
