# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::Identity;

use v5.24;
use strict;
use warnings;
use Scalar::Util qw(blessed);

our $VERSION = '0.3.0';
our @ObjectDependencies = qw(Kernel::Config Kernel::System::DB Kernel::System::D724::Audit Kernel::System::D724::TenantGuard Kernel::System::JSON Kernel::System::Log);

my %Role = map { $_ => 1 } qw(requester agent service_owner auditor tenant_admin);

sub new { return bless {}, $_[0] }

sub ProviderCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_ProviderCreate(%Param) } );
}

sub _ProviderCreate {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize( %Param, Action => 'identity.manage' );
    return $Auth if !$Auth->{Success};
    return $Self->_Error('KEY_INVALID') if ( $Param{Key} // q{} ) !~ m{\A[a-z0-9][a-z0-9._-]{0,99}\z}smx;
    return $Self->_Error('ISSUER_INVALID') if ( $Param{Issuer} // q{} ) !~ m{\Ahttps://[A-Za-z0-9.-]+(?::[0-9]+)?(?:/[A-Za-z0-9._~/-]*)?\z}smx || length $Param{Issuer} > 500;
    return $Self->_Error('AUDIENCE_INVALID') if ( $Param{Audience} // q{} ) !~ m{\A[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}\z}smx;
    my $Domains = $Self->_DomainsValidate( $Param{AllowedDomains} );
    return $Domains if !$Domains->{Success};
    my $Map = $Self->_GroupMapValidate( $Param{GroupRoleMap} );
    return $Map if !$Map->{Success};
    return $Self->_Error('PROVIDER_ROUTE_EXISTS') if $Self->_ProviderByRoute( Issuer => $Param{Issuer}, Audience => $Param{Audience} );
    my $JSON = $Kernel::OM->Get('Kernel::System::JSON');
    my ( $DomainsJSON, $MapJSON ) = (
        $JSON->Encode( Data => $Domains->{Data}, SortKeys => 1 ),
        $JSON->Encode( Data => $Map->{Data}, SortKeys => 1 ),
    );
    my @Value = @Param{qw(TenantID Key Issuer Audience)};
    push @Value, $DomainsJSON, $MapJSON, $Param{UserID}, $Param{UserID};
    my @Bind = map { \$_ } @Value;
    my $OK = $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => q{INSERT INTO d724_identity_provider (tenant_id,key_name,issuer,audience,allowed_domains_json,group_role_map_json,status,version,create_time,create_by,change_time,change_by) VALUES (?,?,?,?,?,?,'active',1,current_timestamp,?,current_timestamp,?)},
        Bind => \@Bind,
    );
    return $Self->_Error('PROVIDER_ROUTE_EXISTS') if !$OK;
    my $Provider = $Self->_ProviderByRoute( Issuer => $Param{Issuer}, Audience => $Param{Audience} );
    my $Audit = $Kernel::OM->Get('Kernel::System::D724::Audit')->Record(
        TenantID => $Param{TenantID}, ActorType => 'agent', ActorID => "agent:$Param{UserID}",
        Action => 'identity.provider.created', ObjectType => 'identity_provider', ObjectID => "$Provider->{ID}",
        CorrelationID => "identity-provider:$Provider->{ID}", DedupeKey => "identity:provider:$Provider->{ID}:version:1",
        FromState => q{}, ToState => 'active', Details => { key => $Param{Key}, issuer => $Param{Issuer}, audience => $Param{Audience} },
    );
    return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audit->{Success};
    return { Success => 1, Data => $Provider };
}

sub VerifiedClaimsResolve {
    my ( $Self, %Param ) = @_;
    return $Self->_TransactionRun( Code => sub { return $Self->_VerifiedClaimsResolve(%Param) } );
}

sub _VerifiedClaimsResolve {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('IDENTITY_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Identity::Enabled');
    my $Verification = $Param{Verification};
    return $Self->_Error('VERIFICATION_REQUIRED') if ref $Verification ne 'HASH' || !$Verification->{Verified};
    return $Self->_Error('VERIFIER_INVALID') if ( $Verification->{Verifier} // q{} ) !~ m{\A(?:oidc|saml)\z}smx;
    my $Provider = $Self->_ProviderByRoute( Issuer => $Verification->{Issuer}, Audience => $Verification->{Audience} );
    return $Self->_Error('TRUST_ROUTE_NOT_FOUND') if !$Provider || $Provider->{Status} ne 'active';
    my $Claims = $Verification->{Claims};
    return $Self->_Error('CLAIMS_INVALID') if ref $Claims ne 'HASH';
    my $Subject = $Claims->{sub} // q{};
    my $Login = lc( $Claims->{preferred_username} // q{} );
    my $Email = lc( $Claims->{email} // q{} );
    return $Self->_Error('SUBJECT_INVALID') if $Subject !~ m{\A[^\x00-\x1f]{1,255}\z}smx;
    return $Self->_Error('LOGIN_INVALID') if $Login !~ m{\A[a-z0-9][a-z0-9._@+-]{0,199}\z}smx;
    return $Self->_Error('EMAIL_INVALID') if $Email !~ m{\A[^\s@]+@[a-z0-9.-]+\z}smx || length $Email > 320;
    my ($Domain) = $Email =~ m{@([a-z0-9.-]+)\z}smx;
    my %AllowedDomain = map { $_ => 1 } @{ $Provider->{AllowedDomains} };
    return $Self->_Error('EMAIL_DOMAIN_DENIED') if !$AllowedDomain{$Domain};
    my $Groups = $Claims->{groups} // [];
    return $Self->_Error('GROUPS_INVALID') if ref $Groups ne 'ARRAY' || @{$Groups} > 200;
    my %Roles = ( requester => 1 );
    for my $Group ( @{$Groups} ) {
        return $Self->_Error('GROUP_INVALID') if !defined $Group || $Group !~ m{\A[^\x00-\x1f]{1,200}\z}smx;
        $Roles{ $Provider->{GroupRoleMap}->{$Group} } = 1 if $Provider->{GroupRoleMap}->{$Group};
    }

    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $ProviderID = $Provider->{ID};
    $DB->Prepare(
        SQL => 'SELECT id,user_login,email,status,version FROM d724_federated_identity WHERE provider_id = ? AND subject_id = ?',
        Bind => [ \$ProviderID, \$Subject ], Limit => 1,
    );
    my ( $IdentityID, $ExistingLogin, $ExistingEmail, $Status, $Version ) = $DB->FetchrowArray();
    my $Created = 0;
    if ($IdentityID) {
        return $Self->_Error('SUBJECT_LOGIN_CONFLICT') if $ExistingLogin ne $Login;
        return $Self->_Error('IDENTITY_INACTIVE') if $Status ne 'active';
        $DB->Do( SQL => 'UPDATE d724_federated_identity SET last_seen=current_timestamp,change_time=current_timestamp WHERE id=?', Bind => [ \$IdentityID ] );
    }
    else {
        my $TenantID = $Provider->{TenantID};
        $DB->Prepare(
            SQL => 'SELECT id FROM d724_federated_identity WHERE tenant_id=? AND user_login=?',
            Bind => [ \$TenantID, \$Login ], Limit => 1,
        );
        my ($LoginIdentityID) = $DB->FetchrowArray();
        return $Self->_Error('LOGIN_ALREADY_LINKED') if $LoginIdentityID;
        my @Value = ( $TenantID, $ProviderID, $Subject, $Login, $Email );
        my @Bind = map { \$_ } @Value;
        return $Self->_Error('LOGIN_ALREADY_LINKED') if !$DB->Do(
            SQL => q{INSERT INTO d724_federated_identity (tenant_id,provider_id,subject_id,user_login,email,status,version,last_seen,create_time,change_time) VALUES (?,?,?,?,?,'active',1,current_timestamp,current_timestamp,current_timestamp)},
            Bind => \@Bind,
        );
        $DB->Prepare( SQL => 'SELECT id FROM d724_federated_identity WHERE provider_id=? AND subject_id=?', Bind => [ \$ProviderID, \$Subject ], Limit => 1 );
        ($IdentityID) = $DB->FetchrowArray();
        $Version = 1;
        $Created = 1;
    }
    if ($Created) {
        my $Audit = $Kernel::OM->Get('Kernel::System::D724::Audit')->Record(
            TenantID => $Provider->{TenantID}, ActorType => 'integration', ActorID => "identity:$Verification->{Verifier}",
            Action => 'identity.subject.linked', ObjectType => 'federated_identity', ObjectID => "$IdentityID",
            CorrelationID => "federated-identity:$IdentityID", DedupeKey => "identity:subject:$IdentityID:version:1",
            FromState => q{}, ToState => 'active', Details => { provider_key => $Provider->{Key}, login => $Login, roles => join( ',', sort keys %Roles ) },
        );
        return $Self->_Error('AUDIT_WRITE_FAILED') if !$Audit->{Success};
    }
    return { Success => 1, Data => {
        TenantID => $Provider->{TenantID}, ProviderKey => $Provider->{Key}, IdentityID => 0 + $IdentityID,
        Subject => $Subject, Login => $Login, Email => $Email, Roles => [ sort keys %Roles ],
        Version => 0 + ( $Version // 1 ), TenantClaimIgnored => exists $Claims->{tenant_id} ? 1 : 0,
    } };
}

sub _ProviderByRoute {
    my ( $Self, %Param ) = @_;
    return if !defined $Param{Issuer} || !defined $Param{Audience};
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => 'SELECT id,tenant_id,key_name,issuer,audience,allowed_domains_json,group_role_map_json,status,version FROM d724_identity_provider WHERE issuer=? AND audience=?',
        Bind => [ \$Param{Issuer}, \$Param{Audience} ], Limit => 1,
    );
    my @Row = $DB->FetchrowArray();
    return if !@Row;
    my $JSON = $Kernel::OM->Get('Kernel::System::JSON');
    return { ID => 0 + $Row[0], TenantID => $Row[1], Key => $Row[2], Issuer => $Row[3], Audience => $Row[4],
        AllowedDomains => $JSON->Decode( Data => $Row[5] ), GroupRoleMap => $JSON->Decode( Data => $Row[6] ), Status => $Row[7], Version => 0 + $Row[8] };
}

sub ProviderRouteGetByKey {
    my ( $Self, %Param ) = @_;
    return if ( $Param{TenantID} // q{} ) !~ m{\A[a-z0-9][a-z0-9_-]{1,127}\z}smx;
    return if ( $Param{ProviderKey} // q{} ) !~ m{\A[a-z0-9][a-z0-9._-]{0,99}\z}smx;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => 'SELECT issuer,audience FROM d724_identity_provider WHERE tenant_id=? AND key_name=? AND status=\'active\'',
        Bind => [ \$Param{TenantID}, \$Param{ProviderKey} ], Limit => 1,
    );
    my ( $Issuer, $Audience ) = $DB->FetchrowArray();
    return if !defined $Issuer;
    return $Self->_ProviderByRoute( Issuer => $Issuer, Audience => $Audience );
}

sub _DomainsValidate {
    my ( $Self, $Domains ) = @_;
    return $Self->_Error('DOMAINS_INVALID') if ref $Domains ne 'ARRAY' || !@{$Domains} || @{$Domains} > 50;
    my %Seen;
    for my $Domain ( @{$Domains} ) {
        return $Self->_Error('DOMAIN_INVALID') if !defined $Domain || $Domain !~ m{\A[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?\z}smx || $Seen{$Domain}++;
    }
    return { Success => 1, Data => [ sort keys %Seen ] };
}

sub _GroupMapValidate {
    my ( $Self, $Map ) = @_;
    return $Self->_Error('GROUP_MAP_INVALID') if ref $Map ne 'HASH' || keys(%{$Map}) > 100;
    for my $Group ( keys %{$Map} ) {
        return $Self->_Error('GROUP_MAP_INVALID') if $Group !~ m{\A[^\x00-\x1f]{1,200}\z}smx || !$Role{ $Map->{$Group} // q{} };
    }
    return { Success => 1, Data => $Map };
}

sub _Authorize {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('IDENTITY_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::Identity::Enabled');
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Param{Subject}, Resource => { TenantID => $Param{TenantID} }, Action => $Param{Action},
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    return { Success => 1 };
}

sub _TransactionRun {
    my ( $Self, %Param ) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Handle = $DB->Connect();
    return $Self->_Error('DATABASE_UNAVAILABLE') if !$Handle;
    return $Param{Code}->() if !$Handle->{AutoCommit};
    my $Result;
    my $OK = eval {
        die "TRANSACTION_START_FAILED\n" if !$DB->BeginWork();
        $Result = $Param{Code}->();
        die "TRANSACTION_RESULT_INVALID\n" if ref $Result ne 'HASH' || !exists $Result->{Success};
        if ( $Result->{Success} ) { die "TRANSACTION_COMMIT_FAILED\n" if !$Handle->commit() }
        else { die "TRANSACTION_ROLLBACK_FAILED\n" if !$DB->Rollback() }
        1;
    };
    if (!$OK) {
        eval { $DB->Rollback() } if !$Handle->{AutoCommit};
        $Kernel::OM->Get('Kernel::System::Log')->Log( Priority => 'error', Message => "CareOnCloud identity transaction failed: " . ( $@ || 'unknown' ) );
        return $Self->_Error('TRANSACTION_FAILED');
    }
    return $Result;
}

sub _Error { return { Success => 0, Error => $_[1], Reason => $_[2] } }

1;
