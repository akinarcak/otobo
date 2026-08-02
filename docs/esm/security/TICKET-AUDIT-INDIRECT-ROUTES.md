# Ticket audit indirect write-route inventory

**Status:** `VERIFIED_BY_CURRENT_TEST` for the Generic Interface update route
and the core scheduler pending-check route on 2026-08-02. This inventory
distinguishes those route-specific results from remaining daemon coverage.

## Generic Interface ticket operations

`Kernel/GenericInterface/Operation/Ticket/TicketCreate.pm` calls the core
`TicketCreate` method, and `TicketUpdate.pm` calls the standard ticket setters:
queue, lock, type, pending time, state, service, SLA, customer, priority,
owner, and responsible. The `D724TicketAudit` method wrappers therefore apply
their tenant-scope and per-mutation audit transaction contract to those calls.

`TicketCreate` and `TicketUpdate` are wrapped at the operation `Run` boundary
in one transaction; nested ticket mutation wrappers use savepoints. The
`TicketCreate` source regression creates a ticket and then forces the enclosing
request to fail, asserting that no ticket row remains. The `TicketUpdate`
candidate regression verifies that a request whose later step fails rolls an
earlier successful title mutation, its scope version, and its audit mutation
back. A current candidate MariaDB rerun is still required before the
`TicketCreate` route is called accepted.

An isolated clean candidate also accepted an authenticated REST request through
`/careoncloud/nph-genericinterface.pl` that changed title and priority in one
request. The database re-read verified both values, scope version `1 -> 3`, the
two normalized audit actions, and a valid tenant audit chain. Evidence:
`/home/test/careoncloud-releases/20260725/.codex-backup-p0-api-20260802/gi-http-acceptance.log`.

## Article backends

The MIME database backend and the separate Chat backend are wrapped and have
candidate MariaDB regression coverage. Chat create, update, and delete writes
use the same scope lock and transaction-aware audit contract, with
`ticket.chat_article.created`, `ticket.chat_article.updated`, and
`ticket.chat_article.deleted` evidence. The candidate regression verifies that
audit-disabled updates and deletes roll the database mutation and scope version
back, then verifies the recovered lifecycle path.

Chat update rebuilds the core article search index. As with core ticket delete,
that external indexing side effect is outside the MariaDB transaction boundary;
the coverage does not claim cross-system atomicity.

## Event, scheduler, and daemon paths

Several inherited ticket event modules call the standard wrapped setters (for
example pending-time reset, forced state/owner changes, and lock actions), so
their individual ticket-field mutations enter the current method wrappers.

`VERIFIED_BY_CURRENT_TEST`: the core `Maint::Ticket::PendingCheck` command was
executed through the real scheduler task-worker fork and Cron handler in a
fresh isolated Compose candidate. The package runs the command per active
tenant under TenantGuard automation authorization and reconciles each observed
state transition with a scope-lock/audit transaction. The retained result
proves the pending-check route advances the ticket scope and audit chain; it
does not cover GenericAgent, other scheduler/daemon jobs, direct DB writes, or
external side effects.
