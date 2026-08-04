# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;
use utf8;

use Test2::V0;
use Kernel::System::UnitTest::RegisterOM;

my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
$LayoutObject->Block(
    Name => 'ServiceSelectOption',
    Data => { ServiceID => 4, Name => 'Workplace <Admin>', Selected => 'selected' },
);
$LayoutObject->Block(
    Name => 'OfferingSelectOption',
    Data => { OfferingID => 7, Name => 'Managed Device', Selected => 'selected' },
);
$LayoutObject->Block(
    Name => 'ItemSelectOption',
    Data => { CatalogItemID => 9, Name => 'Laptop Request' },
);
my $SelectionHTML = $LayoutObject->Output(
    TemplateFile => 'CustomerCareOnCloudCatalog',
    Data => { View => 'Select', ServiceID => 4, OfferingID => 7 },
);
like( $SelectionHTML, qr{id="CareOnCloudServiceID"}, 'customer selects a service category' );
like( $SelectionHTML, qr{id="CareOnCloudOfferingID"}, 'customer selects a service extension' );
like( $SelectionHTML, qr{id="CareOnCloudCatalogItemID"}, 'customer selects a request type' );
like( $SelectionHTML, qr{Workplace\s*&lt;Admin&gt;}, 'category names are HTML escaped' );
$LayoutObject->Block(
    Name => 'ItemDetail',
    Data => { Name => 'Laptop <script>alert(1)</script>', Description => 'Safe description' },
);
$LayoutObject->Block(
    Name => 'FormField',
    Data => { key => 'summary', label => 'Summary <img src=x>', type => 'text', required => 1 },
);
$LayoutObject->Block(
    Name => 'FormField',
    Data => {
        key => 'model', label => 'Model', type => 'select', required => 0,
        options => [ { value => 'standard', label => 'Standard' }, { value => 'dev', label => 'Developer' } ],
    },
);
my $HTML = $LayoutObject->Output(
    TemplateFile => 'CustomerCareOnCloudCatalog',
    Data         => { View => 'Item' },
);

like( $HTML, qr{Laptop\s*&lt;script&gt;alert\(1\)&lt;/script&gt;}, 'item name is HTML escaped' );
unlike( $HTML, qr{<script>alert\(1\)</script>}, 'untrusted item markup is never rendered' );
like( $HTML, qr{id="CareOnCloud_summary"[^>]*type="text"[^>]*required}, 'required text field is rendered' );
like( $HTML, qr{<select[^>]*id="CareOnCloud_model"}, 'select field is rendered' );
like( $HTML, qr{<option value="dev">Developer</option>}, 'select options are rendered' );
like( $HTML, qr{Summary\s*&lt;img src=x&gt;}, 'field label is HTML escaped' );

done_testing;
