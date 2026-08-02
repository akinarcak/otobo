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
- `TicketSLASet`, `TicketPendingTimeSet`, `TicketArchiveFlagSet`, and
  `TicketUnlockTimeoutUpdate`
- `TicketDelete` (retains a `deleted` scope tombstone) and same-tenant `TicketMerge`
- MIMEBase `ArticleCreate`, inherited by the Email, Internal, and Phone
  communication-channel backends

The corresponding tests cover create, state/title/customer mutations, article
creation, audit failure rollback, no-op behavior, and tenant-chain validation
in `packages/D724TicketAudit/scripts/test/D724/TicketAudit.t`.

## Direct ticket mutator inventory

The original P0 inventory is covered and the source comparison additionally
identified and wrapped `TicketArchiveFlagSet` and `TicketUnlockTimeoutUpdate`.
Personal watcher/seen flags (`TicketFlagSet`), ticket dynamic-field writes,
calendar appointment ticket updates, accounted-time writes, escalation-index
maintenance, and article-storage switching remain explicitly outside this
business-mutation coverage claim. These routes were confirmed by direct source
comparison against `Kernel/System/Ticket.pm` and related core callers; no audit
coverage is inferred from their event names. `TicketAudit.t`
verifies archive-flag and delete audit failure rollback, the retained deleted
scope tombstone, and the normalized delete event; later delete calls are fixture
cleanup.

### Unlock-timeout parent transaction contract

`TicketUnlockTimeoutUpdate` writes the core ticket `timeout` field directly and
is now wrapped by the generic mutation contract. `TicketLockSet`, MIMEBase, and
Chat article creation also call it inside their audited parent transaction
without checking its return value, so `D724TicketAudit 0.8.19` uses an explicit,
parent-linked nested-mutation failure context. Any inner mutation failure makes
the parent operation fail closed and roll back. After a successful inner timeout
audit, the parent re-locks the scope and uses the current version for its own
compare-and-swap. Nested execution is enabled only for `TicketLockSet`; other
generic ticket setters retain their existing suppression boundary.

The resulting contract records timeout and its lock/article parent as two
consecutive audit mutations. The regression covers direct calls, the lock
parent, and MIMEBase and Chat article creation. Targeted timeout-only audit
failure must roll every parent mutation back; successful parents must persist
both writes and advance the scope twice. Foundation locks these assertions.
Candidate MariaDB execution is still required before runtime acceptance is
claimed.

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
