# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::TenantCache;

use v5.24;
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

our $VERSION = '0.1.0';
our @ObjectDependencies = (
    'Kernel::Config', 'Kernel::System::Cache', 'Kernel::System::DB',
    'Kernel::System::D724::TenantGuard',
);

sub new { return bless {}, $_[0] }

sub Set {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('VALUE_MISSING') if !exists $Param{Value} || !defined $Param{Value};
    my $Context = $Self->_Context(%Param);
    return $Context if !$Context->{Success};
    my $Maximum = $Kernel::OM->Get('Kernel::Config')->Get('D724::TenantCache::MaximumTTLSeconds') // 86400;
    return $Self->_Error('TTL_CONFIG_INVALID') if $Maximum !~ m{\A[1-9][0-9]{0,5}\z}smx;
    my $TTL = $Param{TTL} // 300;
    return $Self->_Error('TTL_INVALID') if $TTL !~ m{\A[1-9][0-9]*\z}smx || $TTL > $Maximum;
    my $OK = $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type => $Context->{Type}, Key => $Context->{Key}, Value => $Param{Value}, TTL => $TTL,
        CacheInMemory => 0, CacheInBackend => 1,
    );
    return $Self->_Error('CACHE_WRITE_FAILED') if !$OK;
    return { Success => 1, Namespace => $Context->{Namespace}, TTL => 0 + $TTL };
}

sub Get {
    my ( $Self, %Param ) = @_;
    my $Context = $Self->_Context(%Param);
    return $Context if !$Context->{Success};
    my $Value = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => $Context->{Type}, Key => $Context->{Key}, CacheInMemory => 0, CacheInBackend => 1,
    );
    return { Success => 1, Hit => defined $Value ? 1 : 0, Value => $Value, Namespace => $Context->{Namespace} };
}

sub Delete {
    my ( $Self, %Param ) = @_;
    my $Context = $Self->_Context(%Param);
    return $Context if !$Context->{Success};
    my $OK = $Kernel::OM->Get('Kernel::System::Cache')->Delete( Type => $Context->{Type}, Key => $Context->{Key} );
    return $Self->_Error('CACHE_DELETE_FAILED') if !$OK;
    return { Success => 1, Namespace => $Context->{Namespace} };
}

sub TenantCleanUp {
    my ( $Self, %Param ) = @_;
    my $Context = $Self->_Context( %Param, Domain => '_tenant', Key => '_cleanup' );
    return $Context if !$Context->{Success};
    my $OK = $Kernel::OM->Get('Kernel::System::Cache')->CleanUp( Type => $Context->{Type} );
    return $Self->_Error('CACHE_CLEANUP_FAILED') if !$OK;
    return { Success => 1, Namespace => $Context->{Namespace} };
}

sub NamespaceGet {
    my ( $Self, %Param ) = @_;
    my $Valid = $Self->_Identifiers(%Param);
    return $Valid if !$Valid->{Success};
    return { Success => 1, %{ $Self->_Physical(%Param) } };
}

sub _Context {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('CACHE_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::TenantCache::Enabled');
    my $Valid = $Self->_Identifiers(%Param);
    return $Valid if !$Valid->{Success};
    return $Self->_Error('ACTION_MISSING') if !defined $Param{Action} || !length $Param{Action};
    return $Self->_Error('SUBJECT_MISSING') if ref $Param{Subject} ne 'HASH';
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    return $Self->_Error('TENANT_LOOKUP_FAILED') if !$DB->Prepare(
        SQL => "SELECT 1 FROM d724_tenant WHERE key_name = ? AND status = 'active'",
        Bind => [ \$Param{TenantID} ], Limit => 1,
    );
    my ($Active) = $DB->FetchrowArray();
    return $Self->_Error('TENANT_INACTIVE') if !$Active;
    my $Decision = $Kernel::OM->Get('Kernel::System::D724::TenantGuard')->DecisionGet(
        Subject => $Param{Subject}, Resource => { TenantID => $Param{TenantID} }, Action => $Param{Action},
    );
    return $Self->_Error( 'FORBIDDEN', $Decision->{Reason} ) if !$Decision->{Allowed};
    return { Success => 1, %{ $Self->_Physical(%Param) } };
}

sub _Identifiers {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('TENANT_ID_INVALID') if ( $Param{TenantID} // q{} ) !~ m{\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z}smx;
    return $Self->_Error('DOMAIN_INVALID') if ( $Param{Domain} // q{} ) !~ m{\A[a-z][a-z0-9_]{0,31}\z}smx && ( $Param{Domain} // q{} ) ne '_tenant';
    return $Self->_Error('KEY_INVALID') if !length( $Param{Key} // q{} ) || length( $Param{Key} ) > 256 || $Param{Key} =~ m{[\x00-\x1f\x7f]}smx;
    return { Success => 1 };
}

sub _Physical {
    my ( $Self, %Param ) = @_;
    my $TenantHash = sha256_hex( 'tenant:' . $Param{TenantID} );
    my $KeyHash = sha256_hex( join q{:}, 'key', $Param{Domain}, $Param{Key} );
    return {
        Type => 'D724T_' . substr( $TenantHash, 0, 24 ),
        Key => 'v1:' . $Param{Domain} . ':' . substr( $KeyHash, 0, 40 ),
        Namespace => substr( $TenantHash, 0, 16 ),
    };
}

sub _Error {
    my ( $Self, $Error, $Reason ) = @_;
    my $Result = { Success => 0, Error => $Error };
    $Result->{Reason} = $Reason if defined $Reason;
    return $Result;
}

1;
