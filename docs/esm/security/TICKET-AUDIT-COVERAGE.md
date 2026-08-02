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
- `TicketSLASet` and `TicketPendingTimeSet`
- `TicketDelete` (retains a `deleted` scope tombstone) and same-tenant `TicketMerge`
- MIMEBase `ArticleCreate`, inherited by the Email, Internal, and Phone
  communication-channel backends

The corresponding tests cover create, state/title/customer mutations, article
creation, audit failure rollback, no-op behavior, and tenant-chain validation
in `packages/D724TicketAudit/scripts/test/D724/TicketAudit.t`.

## Direct ticket mutator inventory

The known direct core ticket mutators identified in the original P0 inventory
are wrapped. `TicketAudit.t` verifies delete audit failure rollback, the retained deleted
scope tombstone, and the normalized delete event; later delete calls are fixture
cleanup.

## Implementation order and acceptance gate

1. Keep every newly discovered direct ticket write behind the same immutable
   scope and audit transaction contract.
2. Test each new adapter for success, audit-disabled rollback, cross-tenant
   rejection where applicable, no orphan audit event, and chain verification.
3. Run the package test against the candidate MariaDB runtime and retain its
   output before calling the path covered.

`TicketDelete` database state and audit/scope tombstone are verified together,
but core index and storage hooks can have external side effects. In the current
candidate run Elasticsearch reported a delete version conflict after the DB
rollback path, so full cross-system atomicity is not claimed.

The separate Chat backend has its own create/update/delete wrappers and
candidate regression coverage. The fallback `Invalid` backend intentionally
does not create or update articles, but it can delete unknown-channel metadata
through its own path; that exceptional delete route remains a separate P0
inventory item. Generic Interface write adapters and scheduler/daemon mutations
remain separate P0 items. Generic Interface read/history/update access policy
exists, but it is not evidence of transaction-atomic audit coverage for every
write route.
