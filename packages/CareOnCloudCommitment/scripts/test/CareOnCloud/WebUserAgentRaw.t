# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24;
use strict;
use warnings;
use Test2::V0;
use HTTP::Response ();
use Kernel::System::UnitTest::RegisterOM;
use Kernel::System::WebUserAgent ();

my $Agent = $Kernel::OM->Get('Kernel::System::WebUserAgent');
my $Captured;
{
    no warnings 'redefine';
    local *LWP::UserAgent::request = sub {
        my ( $Self, $Request ) = @_;
        $Captured = $Request;
        return HTTP::Response->new( 202, 'Accepted', [], 'accepted' );
    };
    my %Response = $Agent->Request(
        URL => 'https://hooks.example.test/careoncloud', Type => 'POST',
        RawData => '{"canonical":true}', Header => { 'Content-Type' => 'application/json' }, NoLog => 1,
    );
    like( $Response{Status}, qr{\A202}, 'raw request returns the transport status' );
}
is( $Captured->content(), '{"canonical":true}', 'raw body reaches HTTP::Request byte-for-byte' );
my %Invalid = $Agent->Request(
    URL => 'https://hooks.example.test/careoncloud', Type => 'POST', RawData => '{}', Data => { duplicate => 1 }, NoLog => 1,
);
is( $Invalid{Status}, 0, 'raw body and form data cannot be combined' );

done_testing;
