#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use HTTP::Tiny ();
use JSON::PP ();
use Kernel::System::ObjectManager;

my $Password = $ENV{D724_GI_ACCEPTANCE_PASSWORD} // q{};
die "D724_GI_ACCEPTANCE_PASSWORD is required\n" if length $Password < 16;

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $JSON       = JSON::PP->new->canonical;
my $UserID     = 2; # quick_setup.pl's explicitly-created admin user
my $TenantID   = 'gi-acceptance';
my $ServiceName = 'D724AcceptanceTicketUpdate';
my $Webservice = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice');
my $ServiceID;

END {
    return if !$ServiceID || !$Kernel::OM;
    eval { $Webservice->WebserviceDelete( ID => $ServiceID, UserID => $UserID ) };
}

my $Bootstrap = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory')->Bootstrap(
    Confirm => 1, TenantID => $TenantID, Name => 'Generic Interface acceptance', UserID => $UserID,
);
die "tenant bootstrap failed\n" if !$Bootstrap->{Success};

my $Ticket = $Kernel::OM->Get('Kernel::System::Ticket');
my $TicketID = $Ticket->TicketCreate(
    TN => 'D724GI' . time(), Title => 'Generic Interface acceptance before update',
    Queue => 'Raw', Lock => 'unlock', State => 'new', Priority => '3 normal',
    CustomerID => $TenantID, CustomerUser => 'gi.acceptance', OwnerID => $UserID, UserID => $UserID,
);
die "ticket create failed\n" if !$TicketID;
my $Before = $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID );
die "ticket scope missing\n" if !$Before || $Before->{Version} != 1;

$ServiceID = $Webservice->WebserviceAdd(
    Name => $ServiceName,
    ValidID => 1,
    UserID => $UserID,
    Config => {
        Debugger => { DebugThreshold => 'error', TestMode => '0' },
        Provider => {
            Operation => {
                TicketUpdate => {
                    Description => 'Ephemeral D724 Generic Interface acceptance endpoint',
                    MappingInbound => {}, MappingOutbound => {}, Type => 'Ticket::TicketUpdate',
                },
            },
            Transport => {
                Type => 'HTTP::REST',
                Config => { RouteOperationMapping => { TicketUpdate => { RequestMethod => ['POST'], Route => '/TicketUpdate' } } },
            },
        },
    },
);
die "webservice add failed\n" if !$ServiceID;

my $NewTitle = 'Generic Interface acceptance after update';
local @ENV{qw(http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY)};
delete @ENV{qw(http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY)};
my $Response = HTTP::Tiny->new( timeout => 20 )->post(
    "http://127.0.0.1:5000/careoncloud/nph-genericinterface.pl/Webservice/$ServiceName/TicketUpdate",
    {
        headers => { 'content-type' => 'application/json' },
        content => $JSON->encode({
            UserLogin => 'admin', Password => $Password, TicketID => 0 + $TicketID,
            Ticket => { Title => $NewTitle, Priority => '4 high' },
        }),
    },
);
die "Generic Interface HTTP response failed: $Response->{status}\n" if !$Response->{success};
my $Payload = eval { $JSON->decode( $Response->{content} ) };
if ( !$Payload || ref $Payload ne 'HASH' || ( $Payload->{TicketID} // 0 ) != $TicketID ) {
    my $ContentType = $Response->{headers}->{'content-type'} // q{};
    my $Preview = substr( $Response->{content} // q{}, 0, 240 );
    $Preview =~ s{[^\x20-\x7e]}{ }gsmx;
    die "Generic Interface response is invalid ($ContentType): $Preview\n";
}

$Ticket->_TicketCacheClear( TicketID => $TicketID );
my %Updated = $Ticket->TicketGet( TicketID => $TicketID, DynamicFields => 0, UserID => $UserID );
die "HTTP title update did not persist\n" if $Updated{Title} ne $NewTitle;
die "HTTP priority update did not persist\n" if $Updated{Priority} ne '4 high';
my $After = $Kernel::OM->Get('Kernel::System::D724::TicketAudit')->ScopeGet( TicketID => $TicketID );
die "HTTP update did not advance scope for both fields\n" if !$After || $After->{Version} != 3;

my $Subject = { ID => 'gi-acceptance', TenantIDs => [$TenantID], RoleBindings => { $TenantID => ['tenant_admin'] } };
my $Events = $Kernel::OM->Get('Kernel::System::D724::Audit')->List(
    Subject => $Subject, TenantID => $TenantID, ObjectType => 'ticket', ObjectID => "$TicketID", Limit => 100,
);
die "audit list failed\n" if !$Events->{Success};
my %Action = map { $_->{Action} => 1 } @{ $Events->{Data} };
die "HTTP update audit events missing\n" if !$Action{'ticket.title.updated'} || !$Action{'ticket.priority.updated'};
my $Verify = $Kernel::OM->Get('Kernel::System::D724::Audit')->Verify( Subject => $Subject, TenantID => $TenantID );
die "audit chain verification failed\n" if !$Verify->{Success} || !$Verify->{Valid};

say $JSON->pretty->encode({ success => JSON::PP::true, ticket_id => 0 + $TicketID, scope_version => 0 + $After->{Version} });
