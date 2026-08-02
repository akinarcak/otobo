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
- `TicketSLASet`, `TicketPendingTimeSet`, and `TicketArchiveFlagSet`
- `TicketDelete` (retains a `deleted` scope tombstone) and same-tenant `TicketMerge`
- MIMEBase `ArticleCreate`, inherited by the Email, Internal, and Phone
  communication-channel backends

The corresponding tests cover create, state/title/customer mutations, article
creation, audit failure rollback, no-op behavior, and tenant-chain validation
in `packages/D724TicketAudit/scripts/test/D724/TicketAudit.t`.

## Direct ticket mutator inventory

The original P0 inventory is covered and the source comparison additionally
identified and wrapped `TicketArchiveFlagSet`. Personal watcher/seen flags,
accounted-time writes, escalation-index maintenance, and article-storage switching
remain explicitly outside this business-mutation coverage claim. `TicketAudit.t`
verifies archive-flag and delete audit failure rollback, the retained deleted
scope tombstone, and the normalized delete event; later delete calls are fixture
cleanup.

### Open P0 design decision: unlock-timeout writes

`TicketUnlockTimeoutUpdate` writes the core ticket `timeout` field directly and
is not currently wrapped. A direct application of the generic mutation wrapper
is unsafe: MIMEBase and Chat article creation call this method inside their own
audited transaction but do not check its return value. A nested timeout audit
could therefore fail while article creation continues. If it succeeds and
advances the ticket scope, the enclosing article audit still attempts its
compare-and-swap with the earlier scope version and can fail with
`VERSION_CONFLICT`.

This route requires an explicit higher-model design decision before code changes:

1. Record timeout and article creation as two consecutive audit mutations, make
   nested failure abort the parent operation, and refresh/lock the scope version
   before the parent audit; or
2. coalesce the derived timeout change into the parent article audit while keeping
   direct timeout calls independently audited through an explicit parent context.

Acceptance must cover direct calls plus MIMEBase and Chat article creation,
audit-disabled rollback of both writes, consecutive or coalesced scope semantics,
no orphan audit event, no silently ignored nested failure, and tenant-chain
verification. Until that decision and candidate regression are complete,
unlock-timeout audit completeness is not claimed.

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
candidate regression coverage. `D724TicketAudit 0.8.15` also wraps the fallback
`Invalid` backend's unknown-channel metadata delete route in its own
scope/audit transaction. Its candidate regression is still required before the
route is accepted. Generic Interface write adapters and scheduler/daemon
mutations remain separate P0 items. Generic Interface read/history/update
access policy exists, but it is not evidence of transaction-atomic audit
coverage for every write route.
