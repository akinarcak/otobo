# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::APIAuth;

use v5.24;
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use Encode ();

our $VERSION = '0.5.0';
our @ObjectDependencies = (
    'Kernel::Config', 'Kernel::System::D724::Audit', 'Kernel::System::D724::TenantGuard',
    'Kernel::System::DB', 'Kernel::System::Log', 'Kernel::System::Main',
);

my %ValidRole = map { $_ => 1 } qw(requester agent service_owner auditor automation tenant_admin);

sub new { return bless {}, $_[0] }

sub ClientCreate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('API_DISABLED') if !$Self->_Enabled();
    my $Validation = $Self->_ClientValidate(%Param); return $Validation if !$Validation->{Success};
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Param{Subject}, Resource => { TenantID => $Param{TenantID} }, Action => 'tenant.manage',
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};

    my $ClientID = $Param{ClientID} // 'd724_' . $Kernel::OM->Get('Kernel::System::Main')->GenerateRandomString(
        Length => 32, Dictionary => [ 0 .. 9, 'a' .. 'z' ],
    );
    return $Self->_Error('CLIENT_ID_INVALID') if $ClientID !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{7,127}\z}smx;
    my $Secret = $Kernel::OM->Get('Kernel::System::Main')->GenerateRandomString( Length => 64 );
    my $Hash = $Self->_SecretHash($Secret); return $Self->_Error('BCRYPT_UNAVAILABLE') if !$Hash;

    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Handle = $DB->Connect(); return $Self->_Error('DATABASE_UNAVAILABLE') if !$Handle;
    my $Result; my $OK = eval {
        $DB->BeginWork() if $Handle->{AutoCommit};
        my @Values = ( $ClientID, @Param{qw(TenantID Name)}, $Hash, $Param{Role}, 'active', $Param{TokenTTL}, $Param{RateLimit}, $Param{UserID}, $Param{UserID} );
        my @Bind = map { \$_ } @Values;
        die "CLIENT_INSERT_FAILED\n" if !$DB->Do(
            SQL => 'INSERT INTO d724_api_client (client_id, tenant_id, name, secret_hash, role_name, status, token_ttl, rate_limit, version, create_time, create_by, change_time, change_by) '
                . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, current_timestamp, ?, current_timestamp, ?)', Bind => \@Bind,
        );
        my $Audit = $Self->_Audit(
            TenantID => $Param{TenantID}, ActorID => $Param{Subject}->{ID}, Action => 'api.client.created',
            ClientID => $ClientID, DedupeKey => "api-client:$ClientID:version:1", ToState => 'active',
            Details => { role => $Param{Role}, token_ttl => $Param{TokenTTL}, rate_limit => $Param{RateLimit} },
        );
        die "AUDIT_WRITE_FAILED\n" if !$Audit->{Success};
        $Handle->commit() if !$Handle->{AutoCommit};
        $Result = { Success => 1, Data => { ClientID => $ClientID, ClientSecret => $Secret, TenantID => $Param{TenantID}, Role => $Param{Role}, Version => 1 } };
        1;
    };
    if (!$OK) { my $Failure = $@; eval { $DB->Rollback() } if !$Handle->{AutoCommit}; return $Self->_Error( $Failure =~ /AUDIT/ ? 'AUDIT_WRITE_FAILED' : 'CLIENT_CREATE_FAILED' ) }
    return $Result;
}

sub TokenIssue {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('API_DISABLED') if !$Self->_Enabled();
    return $Self->_Error('INVALID_CLIENT') if ( $Param{ClientID} // q{} ) !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{7,127}\z}smx || !length( $Param{ClientSecret} // q{} );
    my $Client = $Self->_ClientGet( ClientID => $Param{ClientID} );
    return $Self->_Error('INVALID_CLIENT') if !$Client || $Client->{Status} ne 'active' || !$Self->_SecretVerify( $Param{ClientSecret}, $Client->{SecretHash} );
    return $Self->_Error('TENANT_INACTIVE') if !$Self->_TenantActive( TenantID => $Client->{TenantID} );

    my $Token = $Kernel::OM->Get('Kernel::System::Main')->GenerateRandomString( Length => 64 );
    my $TokenHash = sha256_hex($Token); my $TTL = $Client->{TokenTTL};
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Handle = $DB->Connect(); return $Self->_Error('DATABASE_UNAVAILABLE') if !$Handle;
    my $OK = eval {
        $DB->BeginWork() if $Handle->{AutoCommit};
        my @Values = ( $TokenHash, $Client->{ClientID}, $TTL ); my @Bind = map { \$_ } @Values;
        die "TOKEN_INSERT_FAILED\n" if !$DB->Do(
            SQL => "INSERT INTO d724_api_token (token_hash, client_id, expires_at, status, create_time) VALUES (?, ?, DATE_ADD(current_timestamp, INTERVAL ? SECOND), 'active', current_timestamp)",
            Bind => \@Bind,
        );
        my $Fingerprint = substr $TokenHash, 0, 16;
        my $Audit = $Self->_Audit(
            TenantID => $Client->{TenantID}, ActorID => "integration:$Client->{ClientID}",
            Action => 'api.token.issued', ClientID => $Client->{ClientID},
            DedupeKey => "api-token:$Client->{ClientID}:$Fingerprint:issued", ToState => 'active',
            Details => { token_fingerprint => $Fingerprint, expires_in => 0 + $TTL },
        );
        die "AUDIT_WRITE_FAILED\n" if !$Audit->{Success};
        $Handle->commit() if !$Handle->{AutoCommit};
        1;
    };
    if (!$OK) {
        my $Failure = $@; eval { $DB->Rollback() } if !$Handle->{AutoCommit};
        return $Self->_Error( $Failure =~ /AUDIT/ ? 'AUDIT_WRITE_FAILED' : 'TOKEN_ISSUE_FAILED' );
    }
    return { Success => 1, Data => { AccessToken => $Token, TokenType => 'Bearer', ExpiresIn => $TTL, TenantID => $Client->{TenantID}, Role => $Client->{Role} } };
}

sub ClientSecretRotate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('API_DISABLED') if !$Self->_Enabled();
    return $Self->_Error('CLIENT_ID_INVALID')
        if ( $Param{ClientID} // q{} ) !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{7,127}\z}smx;
    return $Self->_Error('TENANT_ID_INVALID')
        if ( $Param{TenantID} // q{} ) !~ m{\A[a-z0-9][a-z0-9_-]{1,127}\z}smx;
    return $Self->_Error('USER_ID_INVALID')
        if ( $Param{UserID} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    return $Self->_Error('VERSION_REQUIRED')
        if ( $Param{ExpectedVersion} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;

    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Param{Subject}, Resource => { TenantID => $Param{TenantID} }, Action => 'tenant.manage',
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    my $Client = $Self->_ClientGet( ClientID => $Param{ClientID} );
    return $Self->_Error('CLIENT_NOT_FOUND')
        if !$Client || $Client->{TenantID} ne $Param{TenantID} || $Client->{Status} ne 'active';
    return $Self->_Error('VERSION_CONFLICT') if $Client->{Version} != $Param{ExpectedVersion};

    my $Secret = $Kernel::OM->Get('Kernel::System::Main')->GenerateRandomString( Length => 64 );
    my $Hash = $Self->_SecretHash($Secret); return $Self->_Error('BCRYPT_UNAVAILABLE') if !$Hash;
    my $NextVersion = $Client->{Version} + 1;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Handle = $DB->Connect(); return $Self->_Error('DATABASE_UNAVAILABLE') if !$Handle;
    my $OK = eval {
        $DB->BeginWork() if $Handle->{AutoCommit};
        my @Values = ( $Hash, $Param{UserID}, $Client->{ClientID}, $Param{TenantID}, $Param{ExpectedVersion} );
        my @Bind = map { \$_ } @Values;
        die "CLIENT_ROTATE_FAILED\n" if !$DB->Do(
            SQL => "UPDATE d724_api_client SET secret_hash = ?, version = version + 1, change_time = current_timestamp, change_by = ? WHERE client_id = ? AND tenant_id = ? AND status = 'active' AND version = ?",
            Bind => \@Bind,
        );
        my $Updated = $Self->_ClientGet( ClientID => $Client->{ClientID} );
        die "VERSION_CONFLICT\n" if !$Updated || $Updated->{Version} != $NextVersion || $Updated->{SecretHash} ne $Hash;
        my $ClientID = $Client->{ClientID};
        die "TOKEN_REVOKE_FAILED\n" if !$DB->Do(
            SQL => "UPDATE d724_api_token SET status = 'revoked' WHERE client_id = ? AND status = 'active'",
            Bind => [ \$ClientID ],
        );
        my $Audit = $Self->_Audit(
            TenantID => $Param{TenantID}, ActorID => $Param{Subject}->{ID}, Action => 'api.client.secret_rotated',
            ClientID => $Client->{ClientID}, DedupeKey => "api-client:$Client->{ClientID}:version:$NextVersion",
            ToState => 'active', Details => { version => $NextVersion, all_active_tokens_revoked => 1 },
        );
        die "AUDIT_WRITE_FAILED\n" if !$Audit->{Success};
        $Handle->commit() if !$Handle->{AutoCommit};
        1;
    };
    if (!$OK) {
        my $Failure = $@; eval { $DB->Rollback() } if !$Handle->{AutoCommit};
        return $Self->_Error('VERSION_CONFLICT') if $Failure =~ /VERSION_CONFLICT/;
        return $Self->_Error( $Failure =~ /AUDIT/ ? 'AUDIT_WRITE_FAILED' : 'CLIENT_ROTATE_FAILED' );
    }
    return { Success => 1, Data => { ClientID => $Client->{ClientID}, ClientSecret => $Secret, TenantID => $Param{TenantID}, Version => $NextVersion } };
}

sub ClientRevoke {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('API_DISABLED') if !$Self->_Enabled();
    return $Self->_Error('CLIENT_ID_INVALID')
        if ( $Param{ClientID} // q{} ) !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{7,127}\z}smx;
    return $Self->_Error('TENANT_ID_INVALID')
        if ( $Param{TenantID} // q{} ) !~ m{\A[a-z0-9][a-z0-9_-]{1,127}\z}smx;
    return $Self->_Error('USER_ID_INVALID')
        if ( $Param{UserID} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;

    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Param{Subject}, Resource => { TenantID => $Param{TenantID} }, Action => 'tenant.manage',
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    my $Client = $Self->_ClientGet( ClientID => $Param{ClientID} );
    return $Self->_Error('CLIENT_NOT_FOUND')
        if !$Client || $Client->{TenantID} ne $Param{TenantID};
    return { Success => 1, Data => { ClientID => $Client->{ClientID}, Status => 'revoked', Version => $Client->{Version} } }
        if $Client->{Status} eq 'revoked';

    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Handle = $DB->Connect();
    return $Self->_Error('DATABASE_UNAVAILABLE') if !$Handle;
    my $NextVersion = $Client->{Version} + 1;
    my $OK = eval {
        $DB->BeginWork() if $Handle->{AutoCommit};
        my @ClientValues = ( $Param{UserID}, $Client->{ClientID}, $Param{TenantID}, $Client->{Version} );
        my @ClientBind = map { \$_ } @ClientValues;
        die "CLIENT_REVOKE_FAILED\n" if !$DB->Do(
            SQL => "UPDATE d724_api_client SET status = 'revoked', version = version + 1, change_time = current_timestamp, change_by = ? WHERE client_id = ? AND tenant_id = ? AND status = 'active' AND version = ?",
            Bind => \@ClientBind,
        );
        my $Updated = $Self->_ClientGet( ClientID => $Client->{ClientID} );
        die "VERSION_CONFLICT\n"
            if !$Updated || $Updated->{Status} ne 'revoked' || $Updated->{Version} != $NextVersion;
        my $ClientID = $Client->{ClientID};
        die "TOKEN_REVOKE_FAILED\n" if !$DB->Do(
            SQL => "UPDATE d724_api_token SET status = 'revoked' WHERE client_id = ? AND status = 'active'",
            Bind => [ \$ClientID ],
        );
        my $Audit = $Self->_Audit(
            TenantID => $Param{TenantID}, ActorID => $Param{Subject}->{ID}, Action => 'api.client.revoked',
            ClientID => $Client->{ClientID}, DedupeKey => "api-client:$Client->{ClientID}:version:$NextVersion",
            ToState => 'revoked', Details => { version => $NextVersion },
        );
        die "AUDIT_WRITE_FAILED\n" if !$Audit->{Success};
        $Handle->commit() if !$Handle->{AutoCommit};
        1;
    };
    if (!$OK) {
        my $Failure = $@;
        eval { $DB->Rollback() } if !$Handle->{AutoCommit};
        return $Self->_Error('VERSION_CONFLICT') if $Failure =~ /VERSION_CONFLICT/;
        return $Self->_Error( $Failure =~ /AUDIT/ ? 'AUDIT_WRITE_FAILED' : 'CLIENT_REVOKE_FAILED' );
    }
    return { Success => 1, Data => { ClientID => $Client->{ClientID}, Status => 'revoked', Version => $NextVersion } };
}

sub TokenValidate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('API_DISABLED') if !$Self->_Enabled();
    return $Self->_Error('TOKEN_INVALID') if ( $Param{AccessToken} // q{} ) !~ m{\A[a-zA-Z0-9]{64}\z}smx;
    my $Hash = sha256_hex( $Param{AccessToken} ); my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => "SELECT c.client_id, c.tenant_id, c.role_name, c.rate_limit, c.status FROM d724_api_token t INNER JOIN d724_api_client c ON c.client_id = t.client_id INNER JOIN d724_tenant d ON d.key_name = c.tenant_id WHERE t.token_hash = ? AND t.status = 'active' AND t.expires_at > current_timestamp AND c.status = 'active' AND d.status = 'active'",
        Bind => [ \$Hash ], Limit => 1,
    );
    my @Row = $DB->FetchrowArray(); return $Self->_Error('TOKEN_INVALID') if !@Row;
    $DB->Do( SQL => 'UPDATE d724_api_token SET last_used_time = current_timestamp WHERE token_hash = ?', Bind => [ \$Hash ] );
    return { Success => 1, Data => { ClientID => $Row[0], TenantID => $Row[1], Role => $Row[2], RateLimit => $Row[3] } };
}

sub Authorize {
    my ( $Self, %Param ) = @_;
    my $Token = $Self->TokenValidate( AccessToken => $Param{AccessToken} ); return $Token if !$Token->{Success};
    return $Self->_Error('CROSS_TENANT') if ( $Param{TenantID} // q{} ) ne $Token->{Data}->{TenantID};
    my $TenantID = $Token->{Data}->{TenantID}; my $Role = $Token->{Data}->{Role};
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => { ID => "integration:$Token->{Data}->{ClientID}", TenantIDs => [$TenantID], RoleBindings => { $TenantID => [$Role] } },
        Resource => { TenantID => $TenantID }, Action => $Param{Action},
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    my $Rate = $Self->_RateConsume( ClientID => $Token->{Data}->{ClientID}, Limit => $Token->{Data}->{RateLimit} );
    return $Rate if !$Rate->{Success};
    return { Success => 1, Data => { %{$Token->{Data}}, Remaining => $Rate->{Remaining}, Subject => { ID => "integration:$Token->{Data}->{ClientID}", TenantIDs => [$TenantID], RoleBindings => { $TenantID => [$Role] } } } };
}

sub TokenRevoke {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('TOKEN_INVALID') if ( $Param{AccessToken} // q{} ) !~ m{\A[a-zA-Z0-9]{64}\z}smx;
    my $Hash = sha256_hex( $Param{AccessToken} );
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare(
        SQL => "SELECT c.client_id, c.tenant_id FROM d724_api_token t INNER JOIN d724_api_client c ON c.client_id = t.client_id WHERE t.token_hash = ? AND t.status = 'active'",
        Bind => [ \$Hash ], Limit => 1,
    );
    my ( $ClientID, $TenantID ) = $DB->FetchrowArray();
    return $Self->_Error('TOKEN_INVALID') if !$ClientID;
    my $Handle = $DB->Connect(); return $Self->_Error('DATABASE_UNAVAILABLE') if !$Handle;
    my $OK = eval {
        $DB->BeginWork() if $Handle->{AutoCommit};
        die "TOKEN_REVOKE_FAILED\n" if !$DB->Do(
            SQL => "UPDATE d724_api_token SET status = 'revoked' WHERE token_hash = ? AND status = 'active'", Bind => [ \$Hash ],
        );
        my $Fingerprint = substr $Hash, 0, 16;
        my $Audit = $Self->_Audit(
            TenantID => $TenantID, ActorID => "integration:$ClientID", Action => 'api.token.revoked',
            ClientID => $ClientID, DedupeKey => "api-token:$ClientID:$Fingerprint:revoked",
            ToState => 'revoked', Details => { token_fingerprint => $Fingerprint },
        );
        die "AUDIT_WRITE_FAILED\n" if !$Audit->{Success};
        $Handle->commit() if !$Handle->{AutoCommit};
        1;
    };
    if (!$OK) {
        my $Failure = $@; eval { $DB->Rollback() } if !$Handle->{AutoCommit};
        return $Self->_Error( $Failure =~ /AUDIT/ ? 'AUDIT_WRITE_FAILED' : 'TOKEN_REVOKE_FAILED' );
    }
    return { Success => 1 };
}

sub _RateConsume {
    my ( $Self, %Param ) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB'); my $ClientID = $Param{ClientID};
    $DB->Prepare( SQL => "SELECT DATE_FORMAT(current_timestamp, '%Y-%m-%d %H:%i:00')" ); my ($Window) = $DB->FetchrowArray();
    my @Values = ( $ClientID, $Window ); my @Bind = map { \$_ } @Values;
    return $Self->_Error('RATE_DATABASE_ERROR') if !$DB->Do(
        SQL => 'INSERT INTO d724_api_rate (client_id, window_start, request_count) VALUES (?, ?, 1) ON DUPLICATE KEY UPDATE request_count = request_count + 1', Bind => \@Bind,
    );
    $DB->Prepare( SQL => 'SELECT request_count FROM d724_api_rate WHERE client_id = ? AND window_start = ?', Bind => \@Bind, Limit => 1 );
    my ($Count) = $DB->FetchrowArray(); return $Self->_Error('RATE_DATABASE_ERROR') if !defined $Count;
    return $Self->_Error('RATE_LIMITED') if $Count > $Param{Limit};
    return { Success => 1, Remaining => $Param{Limit} - $Count };
}

sub _ClientValidate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('TENANT_ID_INVALID') if ( $Param{TenantID} // q{} ) !~ m{\A[a-z0-9][a-z0-9_-]{1,127}\z}smx;
    return $Self->_Error('NAME_INVALID') if !length( $Param{Name} // q{} ) || length $Param{Name} > 200;
    return $Self->_Error('ROLE_INVALID') if !$ValidRole{ $Param{Role} // q{} };
    return $Self->_Error('USER_ID_INVALID') if ( $Param{UserID} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    my $TTLMax = $Kernel::OM->Get('Kernel::Config')->Get('D724::API::TokenTTLMax') // 900;
    my $RateMax = $Kernel::OM->Get('Kernel::Config')->Get('D724::API::RateLimitMax') // 600;
    return $Self->_Error('TOKEN_TTL_INVALID') if ( $Param{TokenTTL} // 0 ) < 60 || $Param{TokenTTL} > $TTLMax;
    return $Self->_Error('RATE_LIMIT_INVALID') if ( $Param{RateLimit} // 0 ) < 1 || $Param{RateLimit} > $RateMax;
    return { Success => 1 };
}

sub _ClientGet {
    my ( $Self, %Param ) = @_; my $ID = $Param{ClientID}; my $DB = $Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare( SQL => 'SELECT client_id, tenant_id, secret_hash, role_name, status, token_ttl, rate_limit, version FROM d724_api_client WHERE client_id = ?', Bind => [ \$ID ], Limit => 1 );
    my @Row = $DB->FetchrowArray(); return if !@Row;
    return { ClientID => $Row[0], TenantID => $Row[1], SecretHash => $Row[2], Role => $Row[3], Status => $Row[4], TokenTTL => $Row[5], RateLimit => $Row[6], Version => $Row[7] };
}

sub _SecretHash {
    my ( $Self, $Secret ) = @_; return if !$Kernel::OM->Get('Kernel::System::Main')->Require('Crypt::Eksblowfish::Bcrypt');
    my $Cost = $Kernel::OM->Get('Kernel::Config')->Get('D724::API::BcryptCost') // 12; $Cost = 9 if $Cost < 9; $Cost = 16 if $Cost > 16;
    my $Salt = $Kernel::OM->Get('Kernel::System::Main')->GenerateRandomString( Length => 16 ); Encode::_utf8_off($Secret);
    my $Octets = Crypt::Eksblowfish::Bcrypt::bcrypt_hash( { key_nul => 1, cost => $Cost, salt => $Salt }, $Secret );
    return "BCRYPT:$Cost:$Salt:" . Crypt::Eksblowfish::Bcrypt::en_base64($Octets);
}

sub _SecretVerify {
    my ( $Self, $Secret, $Stored ) = @_; return if !$Kernel::OM->Get('Kernel::System::Main')->Require('Crypt::Eksblowfish::Bcrypt');
    my ( $Cost, $Salt ) = ( $Stored // q{} ) =~ m{\ABCRYPT:(\d+):(.{16}):}smx; return if !$Cost; Encode::_utf8_off($Secret);
    my $Candidate = "BCRYPT:$Cost:$Salt:" . Crypt::Eksblowfish::Bcrypt::en_base64( Crypt::Eksblowfish::Bcrypt::bcrypt_hash( { key_nul => 1, cost => $Cost, salt => $Salt }, $Secret ) );
    return $Self->_ConstantEqual( $Candidate, $Stored );
}

sub _ConstantEqual { my ( $Self, $A, $B ) = @_; return if length($A) != length($B); my $Diff = 0; for my $I ( 0 .. length($A) - 1 ) { $Diff |= ord( substr $A, $I, 1 ) ^ ord( substr $B, $I, 1 ) } return $Diff == 0 ? 1 : 0 }
sub _TenantActive { my ( $Self, %Param ) = @_; my $ID = $Param{TenantID}; my $DB = $Kernel::OM->Get('Kernel::System::DB'); $DB->Prepare( SQL => "SELECT 1 FROM d724_tenant WHERE key_name = ? AND status = 'active'", Bind => [ \$ID ], Limit => 1 ); my ($OK) = $DB->FetchrowArray(); return $OK }
sub _Audit { my ( $Self, %Param ) = @_; return $Kernel::OM->Get('Kernel::System::D724::Audit')->Record( TenantID => $Param{TenantID}, ActorType => 'integration', ActorID => $Param{ActorID}, Action => $Param{Action}, ObjectType => 'api_client', ObjectID => $Param{ClientID}, CorrelationID => "api-client:$Param{ClientID}", DedupeKey => $Param{DedupeKey}, FromState => q{}, ToState => $Param{ToState}, Outcome => 'success', Details => $Param{Details} ) }
sub _Enabled { return $Kernel::OM->Get('Kernel::Config')->Get('D724::API::Enabled') ? 1 : 0 }
sub _Error { my ( $Self, $Error, $Reason ) = @_; return { Success => 0, Error => $Error, Reason => $Reason // $Error } }

1;
