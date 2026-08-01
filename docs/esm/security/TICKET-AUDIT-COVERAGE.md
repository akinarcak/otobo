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
- database-backed MIME `ArticleCreate`

The corresponding tests cover create, state/title/customer mutations, article
creation, audit failure rollback, no-op behavior, and tenant-chain validation
in `packages/D724TicketAudit/scripts/test/D724/TicketAudit.t`.

## P0 gaps verified in the core API

The upstream-derived core exposes these mutation methods in
`Kernel/System/Ticket.pm`, but the custom module does not currently wrap them:

| Priority | Core method | Core location | Current outcome |
| --- | --- | --- | --- |
| 1 | `TicketDelete` | line 713 | no tenant-scope/audit atomicity guarantee |
| 2 | `TicketMerge` | line 6386 | no source/destination tenant/audit guarantee |
| 3 | `TicketSLASet` | line 3427 | no normalized mutation audit |
| 4 | `TicketPendingTimeSet` | line 4023 | no normalized mutation audit |

The existing `TicketDelete` calls in `TicketAudit.t` are fixture cleanup only;
they do not prove delete auditing or rollback behavior.

## Implementation order and acceptance gate

1. Add `TicketDelete` and `TicketMerge` adapters first. Both must obtain an
   immutable scope before changing data; merge must reject different tenants.
2. Add SLA and pending-time adapters through the existing
   `MutationRun` pattern where the before/after ticket fields are stable.
3. For every adapter add success, audit-disabled rollback, cross-tenant
   rejection where applicable, no orphan audit event, and chain verification.
4. Run the package test against the candidate MariaDB runtime and retain its
   output before calling the path covered.

Chat article, non-MIME article backends, Generic Interface write adapters, and
scheduler/daemon mutations remain separate P0 inventory items. Generic
Interface read/history/update access policy exists, but it is not evidence of
transaction-atomic audit coverage for every write route.
