#!/usr/bin/env perl
# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use JSON::PP ();
use Kernel::System::ObjectManager;

my $Source = $ARGV[0] // '/tmp/elasticsearch-webservice.yml';
local $Kernel::OM = Kernel::System::ObjectManager->new();
my $Main = $Kernel::OM->Get('Kernel::System::Main');
my $Content = $Main->FileRead( Location => $Source ) or die "cannot read $Source\n";
my $Config = $Kernel::OM->Get('Kernel::System::YAML')->Load( Data => ${$Content} );
die "invalid YAML configuration\n" if ref $Config ne 'HASH';
my $Host = $Config->{Requester}->{Transport}->{Config}->{Host} // q{};
die "unsafe Elasticsearch host\n" if $Host ne 'http://elastic:9200';
die "invalid requester transport\n" if ( $Config->{Requester}->{Transport}->{Type} // q{} ) ne 'HTTP::REST';

my $Webservice = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice');
my $Existing = $Webservice->WebserviceGet( Name => 'Elasticsearch' );
my ( $ID, $Mode );
if ( $Existing->{ID} ) {
    die "unexpected existing webservice name\n" if ( $Existing->{Name} // q{} ) ne 'Elasticsearch';
    my $OK = $Webservice->WebserviceUpdate(
        ID => $Existing->{ID}, Name => 'Elasticsearch', Config => $Config, ValidID => 1, UserID => 1,
    );
    die "webservice update failed\n" if !$OK;
    $ID = $Existing->{ID};
    $Mode = 'updated';
}
else {
    $ID = $Webservice->WebserviceAdd(
        Name => 'Elasticsearch', Config => $Config, ValidID => 1, UserID => 1,
    );
    die "webservice add failed\n" if !$ID;
    $Mode = 'created';
}

say JSON::PP->new->canonical->encode({
    success => JSON::PP::true, id => 0 + $ID, mode => $Mode,
    name => 'Elasticsearch', valid_id => 1, host => $Host,
});
