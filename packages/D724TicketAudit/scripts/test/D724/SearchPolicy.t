# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;
use Kernel::System::Ticket::D724AuditCustom ();

$Kernel::OM->ObjectParamAdd( 'Kernel::System::UnitTest::Helper' => { RestoreDatabase => 1 } );
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
$Helper->ConfigSettingChange( Key => 'D724::TenantGuard::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::TenantGuard::AllowPlatformAdmin', Value => 0 );
$Helper->ConfigSettingChange( Key => 'D724::SearchPolicy::Enabled', Value => 1 );
$Helper->ConfigSettingChange( Key => 'D724::SearchPolicy::TenantSafeIndexes', Value => ['ticket'] );
$Helper->ConfigSettingChange( Key => 'CheckEmailAddresses', Value => 0 );
my $DB = $Kernel::OM->Get('Kernel::System::DB');
my $Suffix = lc $Helper->GetRandomID();
my $TenantA = "search-a-$Suffix";
my $TenantB = "search-b-$Suffix";
for my $TenantID ( $TenantA, $TenantB ) {
    my @Values = ( $TenantID, "Search $TenantID", 1, 1 );
    my @Bind = map { \$_ } @Values;
    ok( $DB->Do(
        SQL => "INSERT INTO d724_tenant (key_name, name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, 'active', 1, current_timestamp, ?, current_timestamp, ?)",
        Bind => \@Bind,
    ), "tenant $TenantID created" );
}
my $UserID = $Kernel::OM->Get('Kernel::System::User')->UserAdd(
    UserFirstname => 'Search', UserLastname => 'Policy', UserLogin => "search-policy-$Suffix",
    UserPw => $Helper->GetRandomID(), UserEmail => "search-policy-$Suffix\@example.test",
    ValidID => 1, ChangeUserID => 1,
);
ok( $UserID, 'isolated search-policy agent created' );
my @Role = ( $TenantA, $UserID, 'agent', 1, 1 );
my @RoleBind = map { \$_ } @Role;
ok( $DB->Do(
    SQL => "INSERT INTO d724_tenant_agent_role (tenant_id, user_id, role_name, status, version, create_time, create_by, change_time, change_by) VALUES (?, ?, ?, 'active', 1, current_timestamp, ?, current_timestamp, ?)",
    Bind => \@RoleBind,
), 'agent is bound only to tenant A' );

my $Policy = $Kernel::OM->Get('Kernel::System::D724::SearchPolicy');
my $Context = $Policy->ContextCreate( UserID => $UserID );
ok( $Context->{Success}, 'trusted directory agent receives search context' );
is( $Context->{TenantIDs}, [$TenantA], 'search context contains only assigned tenant' );
is( $Policy->ContextCreate( UserID => 999999 )->{Error}, 'FORBIDDEN', 'unknown agent is denied' );

my $Applied = $Policy->RequestFilterApply(
    Context => $Context,
    Data => { IndexName => 'ticket', Must => [ { match => { Title => 'vpn' } } ], Filter => [] },
);
ok( $Applied->{Success}, 'tenant filter is applied to declared safe ticket index' );
is( $Applied->{Data}->{Filter}->[-1], { terms => { CustomerID => [$TenantA] } }, 'final filter uses exact tenant scope' );
is(
    $Policy->RequestFilterApply( Context => $Context, Data => { IndexName => 'customer', Must => [ { match_all => {} } ] } )->{Reason},
    'INDEX_NOT_TENANT_SAFE', 'global customer index fails closed',
);
is(
    $Policy->RequestFilterApply( Data => { IndexName => 'ticket', Must => [ { match_all => {} } ] } )->{Reason},
    'SEARCH_CONTEXT_MISSING', 'direct ticket search without trusted context fails closed',
);

my $Invoker = bless {}, 'Kernel::GenericInterface::Invoker::Elasticsearch::Search';
my $Direct = $Invoker->PrepareRequest( Data => { IndexName => 'ticket', Must => [ { match_all => {} } ] } );
ok( !$Direct->{Success}, 'shared Elasticsearch invoker rejects direct unscoped request' );
like( $Direct->{ErrorMessage}, qr{SEARCH_CONTEXT_MISSING}, 'direct rejection exposes stable reason' );

my $Prepared;
{
    local $Kernel::System::Ticket::D724AuditCustom::D724SearchContext = $Context;
    $Prepared = $Invoker->PrepareRequest(
        Data => { IndexName => 'ticket', Must => [ { match => { Title => 'vpn' } } ], Filter => [], Limit => 10 },
    );
}
ok( $Prepared->{Success}, 'shared invoker accepts trusted scoped request' );
is(
    $Prepared->{Data}->{query}->{bool}->{filter}->[-1],
    { terms => { CustomerID => [$TenantA] } },
    'serialized Elasticsearch body retains mandatory tenant filter',
);

$Helper->ConfigSettingChange( Key => 'D724::SearchPolicy::Enabled', Value => 0 );
is( $Policy->ContextCreate( UserID => $UserID )->{Reason}, 'SEARCH_POLICY_DISABLED', 'disabled policy fails closed' );

done_testing;
