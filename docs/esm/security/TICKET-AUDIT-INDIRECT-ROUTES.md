# Ticket audit indirect write-route inventory

**Status:** `VERIFIED_IN_CODE` on 2026-08-02. This inventory distinguishes
method-level coverage from request-level atomicity and does not claim runtime
acceptance for every route.

## Generic Interface ticket operations

`Kernel/GenericInterface/Operation/Ticket/TicketCreate.pm` calls the core
`TicketCreate` method, and `TicketUpdate.pm` calls the standard ticket setters:
queue, lock, type, pending time, state, service, SLA, customer, priority,
owner, and responsible. The `D724TicketAudit` method wrappers therefore apply
their tenant-scope and per-mutation audit transaction contract to those calls.

`TicketUpdate` performs its fields sequentially. `D724TicketAudit` now wraps
the operation's `Run` method in one transaction; nested ticket mutation
wrappers use savepoints. The candidate regression verifies that a request whose
later step fails rolls an earlier successful title mutation, its scope version,
and its audit mutation back. This is adapter-boundary coverage; an
authenticated Generic Interface transport contract test with a real multi-field
request is still required before claiming end-to-end transport acceptance.

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
This is only `VERIFIED_IN_CODE`; no long-running daemon candidate regression
has been retained. GenericAgent, scheduler task execution, direct DB writes,
and external side effects need dedicated route-level testing before they can be
called fully covered.
