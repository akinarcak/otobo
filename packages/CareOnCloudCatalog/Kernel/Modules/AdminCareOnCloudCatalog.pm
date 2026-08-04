# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::Modules::AdminCareOnCloudCatalog;

use v5.24;
use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;
    return bless { %Param }, $Type;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $Layout    = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $Request   = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Directory = $Kernel::OM->Get('Kernel::System::CareOnCloud::TenantDirectory');
    my $Catalog   = $Kernel::OM->Get('Kernel::System::CareOnCloud::Catalog');
    my $Guard     = $Kernel::OM->Get('Kernel::System::CareOnCloud::TenantGuard');

    my $Context = $Directory->ContextGet( UserID => $Self->{UserID} );
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Context->{Success};
    my $Subject = $Context->{Subject};
    my @ManageableTenants;
    for my $Candidate ( @{ $Subject->{TenantIDs} } ) {
        my $Decision = $Guard->DecisionGet(
            Subject => $Subject, Resource => { TenantID => $Candidate }, Action => 'catalog.manage',
        );
        push @ManageableTenants, $Candidate if $Decision->{Allowed};
    }
    return $Layout->NoPermission( WithHeader => 'yes' ) if !@ManageableTenants;

    my %Manageable = map { $_ => 1 } @ManageableTenants;
    my $TenantID = $Request->GetParam( Param => 'TenantID' ) // $ManageableTenants[0];
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Manageable{$TenantID};
    my %Call = ( Subject => $Subject, TenantID => $TenantID, UserID => $Self->{UserID} );

    my $Subaction = $Self->{Subaction} // q{};
    if ( $Subaction =~ m{\A(?:ServiceSave|OfferingSave|ItemSave|SchemaSave)\z}smx ) {
        $Layout->ChallengeTokenCheck();
        my $Result = $Self->_Write(
            Subaction => $Subaction, Catalog => $Catalog, Request => $Request, Call => \%Call,
        );
        if ( $Result->{Success} ) {
            return $Layout->Redirect( OP => "Action=AdminCareOnCloudCatalog;TenantID=$TenantID" );
        }
        $Param{Error} = $Result->{Error} // 'UNKNOWN_ERROR';
    }

    for my $AvailableTenant ( sort @ManageableTenants ) {
        my $Tenant = $Directory->TenantGet(
            Subject => $Subject, TenantID => $AvailableTenant, UserID => $Self->{UserID},
        );
        $Layout->Block(
            Name => 'TenantOption',
            Data => {
                TenantID => $AvailableTenant,
                Name     => $Tenant->{Success} ? $Tenant->{Data}->{Name} : $AvailableTenant,
                Selected => $AvailableTenant eq $TenantID ? 'selected' : q{},
            },
        );
    }

    my $Services = $Catalog->ServiceList( Subject => $Subject, TenantID => $TenantID );
    return $Layout->NoPermission( WithHeader => 'yes' ) if !$Services->{Success};
    my ( @ServiceOptions, @OfferingOptions );
    for my $Service ( @{ $Services->{Data} } ) {
        push @ServiceOptions, $Service;
        $Layout->Block( Name => 'ServiceRow', Data => { %{$Service}, TenantID => $TenantID } );
        my $Offerings = $Catalog->OfferingList(
            Subject => $Subject, TenantID => $TenantID, ServiceID => $Service->{ServiceID},
        );
        next if !$Offerings->{Success};
        for my $Offering ( @{ $Offerings->{Data} } ) {
            push @OfferingOptions, $Offering;
            $Layout->Block( Name => 'OfferingRow', Data => { %{$Offering}, ServiceName => $Service->{Name}, TenantID => $TenantID } );
            my $Items = $Catalog->CatalogItemList(
                Subject => $Subject, TenantID => $TenantID, OfferingID => $Offering->{OfferingID},
            );
            next if !$Items->{Success};
            for my $Item ( @{ $Items->{Data} } ) {
                my $Schema = $Catalog->CatalogItemSchemaGet(
                    Subject => $Subject, TenantID => $TenantID, CatalogItemID => $Item->{CatalogItemID},
                );
                my $SchemaJSON = $Schema->{Success}
                    ? $Kernel::OM->Get('Kernel::System::JSON')->Encode(
                        Data => $Schema->{Data}->{Schema}, SortKeys => 1, Pretty => 1,
                    )
                    : q{{"version":1,"fields":[]}};
                $Layout->Block(
                    Name => 'ItemRow',
                    Data => {
                        %{$Item}, OfferingName => $Offering->{Name}, SchemaJSON => $SchemaJSON,
                        TenantID => $TenantID,
                        SchemaVersion => $Schema->{Success} ? $Schema->{Data}->{Version} : q{},
                    },
                );
            }
        }
    }
    $Layout->Block( Name => 'ServiceOption', Data => { %{$_}, TenantID => $TenantID } ) for @ServiceOptions;
    $Layout->Block( Name => 'OfferingOption', Data => { %{$_}, TenantID => $TenantID } ) for @OfferingOptions;

    my $Output = $Layout->Header( Title => 'CareOnCloud Service Catalog' );
    $Output .= $Layout->NavigationBar();
    $Output .= $Layout->Notify( Priority => 'Error', Info => $Param{Error} ) if $Param{Error};
    $Output .= $Layout->Output( TemplateFile => 'AdminCareOnCloudCatalog', Data => { TenantID => $TenantID } );
    $Output .= $Layout->Footer();
    return $Output;
}

sub _Write {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request};
    my $Catalog = $Param{Catalog};
    my %Call    = %{ $Param{Call} };
    my $Get = sub { return $Request->GetParam( Param => $_[0] ) };

    if ( $Param{Subaction} eq 'ServiceSave' ) {
        my %Values = ( Name => $Get->('Name'), Description => $Get->('Description'), Status => $Get->('Status') );
        return $Get->('ServiceID')
            ? $Catalog->ServiceUpdate( %Call, %Values, ServiceID => $Get->('ServiceID'), ExpectedVersion => $Get->('ExpectedVersion') )
            : $Catalog->ServiceCreate( %Call, %Values, Key => $Get->('Key') );
    }
    if ( $Param{Subaction} eq 'OfferingSave' ) {
        my %Values = (
            Name => $Get->('Name'), Description => $Get->('Description'), Status => $Get->('Status'),
            FulfillmentType => $Get->('FulfillmentType'),
        );
        return $Get->('OfferingID')
            ? $Catalog->OfferingUpdate( %Call, %Values, OfferingID => $Get->('OfferingID'), ExpectedVersion => $Get->('ExpectedVersion') )
            : $Catalog->OfferingCreate( %Call, %Values, Key => $Get->('Key'), ServiceID => $Get->('ServiceID') );
    }
    if ( $Param{Subaction} eq 'ItemSave' ) {
        my %Values = (
            Name => $Get->('Name'), Description => $Get->('Description'), Status => $Get->('Status'),
            RequestType => $Get->('RequestType'),
        );
        return $Get->('CatalogItemID')
            ? $Catalog->CatalogItemUpdate( %Call, %Values, CatalogItemID => $Get->('CatalogItemID'), ExpectedVersion => $Get->('ExpectedVersion') )
            : $Catalog->CatalogItemCreate( %Call, %Values, Key => $Get->('Key'), OfferingID => $Get->('OfferingID') );
    }
    my $Schema = eval { $Kernel::OM->Get('Kernel::System::JSON')->Decode( Data => $Get->('SchemaJSON') ) };
    return { Success => 0, Error => 'SCHEMA_JSON_INVALID' } if $@ || ref $Schema ne 'HASH';
    my %Version = length( $Get->('ExpectedVersion') // q{} )
        ? ( ExpectedVersion => $Get->('ExpectedVersion') ) : ();
    return $Catalog->CatalogItemSchemaSet(
        %Call, CatalogItemID => $Get->('CatalogItemID'), Schema => $Schema, %Version,
    );
}

1;
