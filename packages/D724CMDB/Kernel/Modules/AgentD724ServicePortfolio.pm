# --
# CareOnCloud ESM is based on OTOBO.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Modules::AgentD724ServicePortfolio;
use v5.24;use strict;use warnings;
our $ObjectManagerDisabled = 1;
sub new { my ( $Type, %Param ) = @_; return bless { %Param }, $Type; }
sub Run {
    my ( $Self, %Param ) = @_;
    my $Layout = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $Request = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Directory = $Kernel::OM->Get('Kernel::System::D724::TenantDirectory');
    my $Guard = $Kernel::OM->Get('Kernel::System::D724::TenantGuard');
    my $CMDB = $Kernel::OM->Get('Kernel::System::D724::CMDB');
    my $Context = $Directory->ContextGet( UserID => $Self->{UserID} );
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Context->{Success};
    my $Subject = $Context->{Subject};
    my @Tenants = grep {
        $Guard->DecisionGet( Subject => $Subject, Resource => { TenantID => $_ }, Action => 'cmdb.read' )->{Allowed}
    } @{ $Subject->{TenantIDs} };
    return $Layout->NoPermission( WithHeader => 'yes' ) if !@Tenants;
    my %Allowed = map { $_ => 1 } @Tenants;
    my $TenantID = $Request->GetParam( Param => 'TenantID' ) // $Tenants[0];
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Allowed{$TenantID};
    my $ServiceID = $Request->GetParam( Param => 'ServiceID' );
    return $Layout->NoPermission( WithHeader => 'yes' ) if defined $ServiceID && $ServiceID !~ m{\A[1-9][0-9]*\z}smx;
    for my $ID ( sort @Tenants ) {
        my $Tenant = $CMDB->TenantLabelGet( Subject => $Subject, TenantID => $ID );
        $Layout->Block( Name => 'TenantOption', Data => { TenantID => $ID, Name => $Tenant->{Success} ? $Tenant->{Data}->{Name} : $ID, Selected => $ID eq $TenantID ? 'selected' : q{} } );
    }
    my %Call = ( Subject => $Subject, TenantID => $TenantID );
    $Call{ServiceID} = $ServiceID if defined $ServiceID;
    my $Portfolio = $CMDB->PortfolioList(%Call);
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Portfolio->{Success};
    my %Services;
    for my $Row ( @{ $Portfolio->{Data} } ) {
        my $ID = $Row->{ServiceID};
        if ( !$Services{$ID}++ ) { $Layout->Block( Name => 'ServiceRow', Data => { %{$Row} } ); }
        $Layout->Block( Name => 'InstanceRow', Data => { %{$Row} } ) if $Row->{ServiceInstanceID};
    }
    my $Output = $Layout->Header( Title => 'CareOnCloud Service Portfolio' );
    $Output .= $Layout->NavigationBar();
    $Output .= $Layout->Output( TemplateFile => 'AgentD724ServicePortfolio', Data => { TenantID => $TenantID, ServiceID => $ServiceID // q{}, ServiceCount => scalar keys %Services, InstanceCount => scalar grep { $_->{ServiceInstanceID} } @{ $Portfolio->{Data} } } );
    $Output .= $Layout->Footer();
    return $Output;
}
1;
