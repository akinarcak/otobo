# Ticket audit coverage inventory

**Status:** `VERIFIED_IN_CODE` on 2026-08-02. This is an implementation
inventory, not a current full-regression result.

## Covered by the D724TicketAudit custom module

`packages/D724TicketAudit/Kernel/System/Ticket/D724AuditCustom.pm` intercepts
the following core writes and sends them through the transaction-aware
`TicketAudit` service:

- `TicketCreate`
- `TicketTitleUpdate`, `TicketQueueSet`, `TicketCustomerSet`, `TicketLockSet`
- `TicketStateSet`, `TicketTypeSet`, `TicketServiceSet`, `TicketOwnerSet`, `TicketResponsibleSet`, `TicketPrioritySet`
- `TicketDelete` (retains a `deleted` scope tombstone) and same-tenant `TicketMerge`
- database-backed MIME `ArticleCreate`

The corresponding tests cover create, state/title/customer mutations, article
creation, audit failure rollback, no-op behavior, and tenant-chain validation
in `packages/D724TicketAudit/scripts/test/D724/TicketAudit.t`.

## P0 gaps verified in the core API

The upstream-derived core exposes these mutation methods in
`Kernel/System/Ticket.pm`, but the custom module does not currently wrap them:

| Priority | Core method | Core location | Current outcome |
| --- | --- | --- | --- |
| 1 | `TicketSLASet` | line 3427 | no normalized mutation audit |
| 2 | `TicketPendingTimeSet` | line 4023 | no normalized mutation audit |

`TicketAudit.t` now verifies delete audit failure rollback, the retained deleted
scope tombstone, and the normalized delete event; later delete calls are fixture
cleanup.

## Implementation order and acceptance gate

1. Add SLA and pending-time adapters through the existing
   `MutationRun` pattern where the before/after ticket fields are stable.
2. For every adapter add success, audit-disabled rollback, cross-tenant
   rejection where applicable, no orphan audit event, and chain verification.
3. Run the package test against the candidate MariaDB runtime and retain its
   output before calling the path covered.

`TicketDelete` database state and audit/scope tombstone are verified together,
but core index and storage hooks can have external side effects. In the current
candidate run Elasticsearch reported a delete version conflict after the DB
rollback path, so full cross-system atomicity is not claimed.

Chat article, non-MIME article backends, Generic Interface write adapters, and
scheduler/daemon mutations remain separate P0 inventory items. Generic
Interface read/history/update access policy exists, but it is not evidence of
transaction-atomic audit coverage for every write route.
