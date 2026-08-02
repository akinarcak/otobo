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

`TicketUpdate` performs its fields sequentially. It is **not** evidence that a
multi-field Generic Interface request has an all-or-nothing transaction across
all of its setter calls. That request-level atomicity remains a P0 acceptance
gap and requires a dedicated operation-level adapter plus regression coverage.

## Article backends

The MIME database backend and the separate Chat backend are wrapped and have
candidate MariaDB regression coverage. Chat writes use the same scope lock and
transaction-aware audit contract, with `ticket.chat_article.created` evidence.
The scope is limited to article creation; Chat article edits and deletes remain
separate write-route inventory items.

## Event, scheduler, and daemon paths

Several inherited ticket event modules call the standard wrapped setters (for
example pending-time reset, forced state/owner changes, and lock actions), so
their individual ticket-field mutations enter the current method wrappers.
This is only `VERIFIED_IN_CODE`; no long-running daemon candidate regression
has been retained. GenericAgent, scheduler task execution, direct DB writes,
and external side effects need dedicated route-level testing before they can be
called fully covered.
