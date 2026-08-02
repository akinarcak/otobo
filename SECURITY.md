# CareOnCloud ESM Security Policy

## Reporting a vulnerability

Report suspected vulnerabilities privately through the repository's
[GitHub private vulnerability reporting channel](https://github.com/akinarcak/otobo/security/advisories/new).
Do not create a public issue, discussion, or pull request for a suspected
vulnerability. Include the affected version or commit, impact, reproduction
steps, and any proof of concept needed to validate the report.

The project acknowledges a valid report within three business days. Critical
vulnerabilities are targeted for a fix, mitigation, or documented response
within seven calendar days. These are response targets, not a guarantee that a
particular issue can be fully remediated in that period.

If the private reporting control is not enabled in the GitHub repository,
maintainers must enable it before publishing a CareOnCloud release. Public
channels remain out of scope for vulnerability disclosure.

## Supported scope

Before the first versioned CareOnCloud release, the supported source is the
current CareOnCloud ESM development branch and candidate builds made from it.
After versioned releases begin, this table must be replaced with explicit
release lines and end-of-support dates.

| Version | Security support |
| --- | --- |
| Pre-1.0 CareOnCloud ESM candidate builds | Supported on a best-effort security basis; no production-readiness claim |

In scope:

- CareOnCloud ESM source, first-party `D724*` packages, release artifacts and
  official candidate deployments operated by the project.
- Tenant isolation, authentication/authorization, secrets handling, audit,
  API, web, container and deployment configuration defects.

Out of scope:

- Third-party or customer-managed deployments where the project has no
  authorization to test.
- Denial-of-service testing, destructive testing, or access to data that the
  reporter does not own or is not authorized to access.
- Social engineering and issues already public or previously disclosed without
  new material impact.

## Coordinated disclosure and customers

The project coordinates CVE assignment with the reporter and an appropriate
CVE Numbering Authority when a CVE is warranted. Managed customers affected by
a confirmed vulnerability receive a private advisory containing the impact,
mitigation, remediation status, and any required action before or alongside
public disclosure when practical.

Reporters acting in good faith, preserving privacy, and avoiding service
disruption will not be subject to legal action by the project for the research
described in their report. Disclosure is coordinated with the reporter; the
default target is no later than 90 days after acknowledgement unless users need
earlier notice or a fix requires a different timeline.

## Upstream relationship

CareOnCloud ESM is derived from OTOBO. Upstream OTOBO vulnerabilities may also
need to be reported to the upstream project, but CareOnCloud reports are in
scope here and are not excluded because this repository is a fork.
