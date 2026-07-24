# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 } );
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $DB     = $Kernel::OM->Get('Kernel::System::DB');
my $Ticket = $Kernel::OM->Get('Kernel::System::Ticket');
my $Auth   = $Kernel::OM->Get('Kernel::System::D724::APIAuth');
my $API    = $Kernel::OM->Get('Kernel::System::D724::API');
my $Suffix = lc $Helper->GetRandomID();
my $Tenant = "api-read-$Suffix";
my $Other  = "api-hidden-$Suffix";

for my $Setting (
    [ 'D724::API::Enabled', 1 ], [ 'D724::API::BcryptCost', 9 ],
    [ 'D724::API::TokenTTLMax', 900 ], [ 'D724::API::RateLimitMax', 100 ],
    [ 'D724::Audit::Enabled', 1 ], [ 'D724::TicketAudit::Enabled', 1 ],
    [ 'D724::TenantGuard::Enabled', 1 ], [ 'D724::TicketPolicy::Enabled', 0 ],
) {
    $Helper->ConfigSettingChange( Key => $Setting->[0], Value => $Setting->[1] );
}

for my $TenantID ( $Tenant, $Other ) {
    my @Values = ( $TenantID, "API Read $TenantID", 1, 1 );
    my @Bind = map { \$_ } @Values;
    ok( $DB->Do(
        SQL => "INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, 'active', 1, current_timestamp, ?, current_timestamp, ?)",
        Bind => \@Bind,
    ), "tenant fixture $TenantID created" );
}

my $QueueID    = $Kernel::OM->Get('Kernel::System::Queue')->QueueLookup( Queue => 'Raw' );
my $StateID    = $Kernel::OM->Get('Kernel::System::State')->StateLookup( State => 'new' );
my $PriorityID = $Kernel::OM->Get('Kernel::System::Priority')->PriorityLookup( Priority => '3 normal' );
my @TicketIDs;
for my $TenantID ( $Tenant, $Other ) {
    push @TicketIDs, $Ticket->TicketCreate(
        TN => 'D724API' . $Helper->GetRandomID(), Title => "API ticket $TenantID",
        QueueID => $QueueID, Lock => 'unlock', StateID => $StateID, PriorityID => $PriorityID,
        CustomerID => $TenantID, CustomerUser => "user-$TenantID", OwnerID => 1, UserID => 1,
    );
}
ok( $TicketIDs[0] && $TicketIDs[1], 'two tenant-bound tickets created' );

my $Admin = { ID => 'api-test-admin', TenantIDs => [$Tenant], RoleBindings => { $Tenant => ['tenant_admin'] } };
my $Created = $Auth->ClientCreate(
    Subject => $Admin, TenantID => $Tenant, Name => 'Read API Test', Role => 'requester',
    UserID => 1, TokenTTL => 60, RateLimit => 20, ClientID => "read-$Tenant",
);
ok( $Created->{Success}, 'tenant API client created' );
my $Issued = $Auth->TokenIssue(
    ClientID => $Created->{Data}->{ClientID}, ClientSecret => $Created->{Data}->{ClientSecret},
);
ok( $Issued->{Success}, 'tenant API token issued' );
my $Token = $Issued->{Data}->{AccessToken};

my $List = $API->TicketList( AccessToken => $Token, TenantID => $Tenant, Limit => 100 );
ok( $List->{Success}, 'tenant ticket list succeeds' );
is( [ map { $_->{id} } @{ $List->{Data}->{items} } ], [ $TicketIDs[0] ], 'list contains only the authorized tenant ticket' );
is( $List->{Data}->{items}->[0]->{tenant_id}, $Tenant, 'response carries the exact tenant boundary' );
is( $List->{Data}->{next_cursor}, undef, 'short result has no cursor' );

my $Get = $API->TicketGet( AccessToken => $Token, TenantID => $Tenant, TicketID => $TicketIDs[0] );
ok( $Get->{Success}, 'same-tenant ticket get succeeds' );
is( $Get->{Data}->{title}, "API ticket $Tenant", 'safe ticket projection is returned' );
is( $API->TicketGet( AccessToken => $Token, TenantID => $Tenant, TicketID => $TicketIDs[1] )->{Error}, 'NOT_FOUND', 'cross-tenant ticket is hidden as not found' );
is( $API->TicketList( AccessToken => $Token, TenantID => $Other, Limit => 10 )->{Error}, 'CROSS_TENANT', 'caller cannot select another tenant' );
is( $API->TicketList( AccessToken => $Token, TenantID => $Tenant, Limit => 101 )->{Error}, 'LIMIT_INVALID', 'oversized page fails before database access' );
is( $API->TicketList( AccessToken => $Token, TenantID => $Tenant, AfterID => '1 OR 1=1' )->{Error}, 'CURSOR_INVALID', 'cursor injection is rejected' );

my $ClientID = $Created->{Data}->{ClientID};
ok( $DB->Do( SQL => 'DELETE FROM d724_api_rate WHERE client_id = ?', Bind => [ \$ClientID ] ), 'rate fixtures removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_api_token WHERE client_id = ?', Bind => [ \$ClientID ] ), 'token fixtures removed' );
ok( $DB->Do( SQL => 'DELETE FROM d724_api_client WHERE client_id = ?', Bind => [ \$ClientID ] ), 'client fixture removed' );
for my $TicketID (@TicketIDs) {
    ok( $DB->Do( SQL => 'DELETE FROM d724_ticket_scope WHERE ticket_id = ?', Bind => [ \$TicketID ] ), "ticket scope $TicketID removed" );
    ok( $Ticket->TicketDelete( TicketID => $TicketID, UserID => 1 ), "core ticket $TicketID removed" );
}
for my $TenantID ( $Tenant, $Other ) {
    ok( $DB->Do( SQL => 'DELETE FROM d724_audit_event WHERE tenant_id = ?', Bind => [ \$TenantID ] ), "audit events $TenantID removed" );
    ok( $DB->Do( SQL => 'DELETE FROM d724_audit_head WHERE tenant_id = ?', Bind => [ \$TenantID ] ), "audit head $TenantID removed" );
    ok( $DB->Do( SQL => 'DELETE FROM d724_tenant WHERE key_name = ?', Bind => [ \$TenantID ] ), "tenant $TenantID removed" );
}

done_testing;
