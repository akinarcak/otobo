# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::APIStatus;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.5.0';
our @ObjectDependencies = (
    'Kernel::Config', 'Kernel::System::DB', 'Kernel::System::JSON', 'Kernel::System::Main',
);

sub Configure {
    my ($Self) = @_;
    $Self->Description('Validate D724 API authorization storage, transport and operational invariants.');
    $Self->AddOption(
        Name => 'json', Description => 'Print JSON.', Required => 0, HasValue => 0,
    );
    return;
}

sub StatusData {
    my ($Self) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my %Table = map { $_ => 1 } $DB->ListTables();
    my @Needed = qw(d724_api_client d724_api_token d724_api_rate);
    my @Missing = grep { !$Table{$_} } @Needed;
    my %Count = map { $_ => 0 } qw(
        Clients ActiveClients RevokedClients Tokens ActiveTokens RevokedTokens
        ExpiredActiveTokens RateWindows CurrentWindowRequests StaleTokenDigests
        StaleRateWindows InvalidTenantClients InvalidSecretHashes InvalidTokenHashes
        DuplicateRateWindows RateWindowUnique QueryErrors
    );

    my $Config = $Kernel::OM->Get('Kernel::Config');
    my $TokenDays = $Config->Get('D724::API::TokenRetentionDays') // 30;
    my $RateHours = $Config->Get('D724::API::RateRetentionHours') // 48;
    my $RetentionValid = $TokenDays =~ m{\A[1-9][0-9]{0,3}\z}smx
        && $RateHours =~ m{\A[1-9][0-9]{0,4}\z}smx ? 1 : 0;

    if ( !@Missing ) {
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COUNT(*), SUM(status = 'active'), SUM(status = 'revoked') FROM d724_api_client",
            Keys => [qw(Clients ActiveClients RevokedClients)],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COUNT(*), SUM(status = 'active' AND expires_at > current_timestamp), SUM(status = 'revoked'), SUM(status = 'active' AND expires_at <= current_timestamp) FROM d724_api_token",
            Keys => [qw(Tokens ActiveTokens RevokedTokens ExpiredActiveTokens)],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COUNT(*), COALESCE(SUM(CASE WHEN window_start = DATE_FORMAT(current_timestamp, '%Y-%m-%d %H:%i:00') THEN request_count ELSE 0 END), 0) FROM d724_api_rate",
            Keys => [qw(RateWindows CurrentWindowRequests)],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COUNT(*) FROM d724_api_client c LEFT JOIN d724_tenant t ON t.key_name = c.tenant_id AND t.status = 'active' WHERE t.key_name IS NULL",
            Keys => ['InvalidTenantClients'],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => "SELECT COUNT(*) FROM d724_api_client WHERE secret_hash NOT LIKE 'BCRYPT:%'",
            Keys => ['InvalidSecretHashes'],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => q{SELECT COUNT(*) FROM d724_api_token WHERE token_hash NOT REGEXP '^[0-9a-f]{64}$'},
            Keys => ['InvalidTokenHashes'],
        );
        $Self->_Query(
            DB => $DB, Count => \%Count,
            SQL => 'SELECT COUNT(*) FROM (SELECT client_id, window_start, COUNT(*) n FROM d724_api_rate GROUP BY client_id, window_start HAVING n > 1) d',
            Keys => ['DuplicateRateWindows'],
        );
        my %Index;
        $Self->_Query(
            DB => $DB, Count => \%Index,
            SQL => "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = 'd724_api_rate' AND index_name = 'd724_api_rate_window'",
            Keys => ['Columns'],
        );
        $Count{QueryErrors} += $Index{QueryErrors} // 0;
        $Count{RateWindowUnique} = ( $Index{Columns} // 0 ) == 2 ? 1 : 0;

        if ($RetentionValid) {
            $Self->_Query(
                DB => $DB, Count => \%Count,
                SQL => "SELECT COUNT(*) FROM d724_api_token WHERE (status = 'revoked' OR expires_at <= current_timestamp) AND create_time < DATE_SUB(current_timestamp, INTERVAL ? DAY)",
                Bind => [ \$TokenDays ], Keys => ['StaleTokenDigests'],
            );
            $Self->_Query(
                DB => $DB, Count => \%Count,
                SQL => 'SELECT COUNT(*) FROM d724_api_rate WHERE window_start < DATE_SUB(current_timestamp, INTERVAL ? HOUR)',
                Bind => [ \$RateHours ], Keys => ['StaleRateWindows'],
            );
        }
    }
    $_ //= 0 for values %Count;

    my $Home = $Config->Get('Home');
    my $Main = $Kernel::OM->Get('Kernel::System::Main');
    my $OpenAPI = $Main->FileRead(
        Location => "$Home/var/httpd/htdocs/d724/api/openapi-v1.json",
        Mode => 'utf8', Result => 'SCALAR',
    );
    my $Contract = $OpenAPI
        ? eval { $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => ${$OpenAPI} ) }
        : undef;
    my $ContractOK = $OpenAPI && !$@ && ref $Contract eq 'HASH'
        && ( $Contract->{openapi} // q{} ) eq '3.1.0' ? 1 : 0;
    my $PSGI = $Main->FileRead(
        Location => "$Home/bin/psgi-bin/otobo.psgi", Mode => 'utf8', Result => 'SCALAR',
    );
    my $MountOK = $PSGI && ${$PSGI} =~ m{mount[ ]+'/api/v1'}smx ? 1 : 0;

    my $Success = !@Missing && $RetentionValid && $Count{RateWindowUnique}
        && !$Count{QueryErrors} && !$Count{InvalidTenantClients}
        && !$Count{InvalidSecretHashes} && !$Count{InvalidTokenHashes}
        && !$Count{DuplicateRateWindows} && $ContractOK && $MountOK;
    return {
        Success => $Success ? 1 : 0, Package => 'D724API', Version => $VERSION,
        Enabled => $Config->Get('D724::API::Enabled') ? 1 : 0,
        MissingTables => \@Missing, Counts => \%Count,
        Retention => {
            Valid => $RetentionValid, TokenDays => 0 + $TokenDays, RateHours => 0 + $RateHours,
        },
        Transport => { CanonicalMount => $MountOK, OpenAPI31 => $ContractOK },
    };
}

sub _Query {
    my ( $Self, %Param ) = @_;
    my %Prepare = ( SQL => $Param{SQL} );
    $Prepare{Bind} = $Param{Bind} if $Param{Bind};
    if ( !$Param{DB}->Prepare(%Prepare) ) {
        $Param{Count}->{QueryErrors}++;
        return;
    }
    my @Row = $Param{DB}->FetchrowArray();
    if ( !@Row ) {
        $Param{Count}->{QueryErrors}++;
        return;
    }
    @{$Param{Count}}{ @{ $Param{Keys} } } = @Row;
    return 1;
}

sub Run {
    my ($Self) = @_;
    my $Status = $Self->StatusData();
    if ( $Self->GetOption('json') ) {
        $Self->Print(
            $Kernel::OM->Get('Kernel::System::JSON')->Encode(
                Data => $Status, SortKeys => 1, Pretty => 1,
            ) . "\n",
        );
    }
    else {
        $Self->Print("D724API $VERSION: " . ( $Status->{Success} ? 'OK' : 'FAILED' ) . "\n");
    }
    return $Status->{Success} ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
