# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::Console::Command::Admin::D724::ReportExport;
use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our $VERSION = '0.1.0';
our @ObjectDependencies = ('Kernel::System::D724::Reporting');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Export a tenant-scoped, privacy-minimized D724 operational report.');
    for my $Option (
        [ 'tenant-id', 'Tenant identifier.', '^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$' ],
        [ 'from', 'Inclusive date (YYYY-MM-DD).', '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ],
        [ 'to', 'Inclusive date (YYYY-MM-DD).', '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ],
        [ 'actor-user-id', 'Directory agent user ID.', '^[1-9][0-9]*$' ],
        [ 'format', 'csv or json.', '^(?:csv|json)$' ],
    ) {
        $Self->AddOption( Name => $Option->[0], Description => $Option->[1], Required => 1, HasValue => 1, ValueRegex => qr{$Option->[2]} );
    }
    return;
}

sub Run {
    my ($Self) = @_;
    my $Result = $Kernel::OM->Get('Kernel::System::D724::Reporting')->Export(
        TenantID => $Self->GetOption('tenant-id'), From => $Self->GetOption('from'),
        To => $Self->GetOption('to'), UserID => $Self->GetOption('actor-user-id'),
        Format => $Self->GetOption('format'),
    );
    if ( !$Result->{Success} ) {
        $Self->PrintError("Report export failed: $Result->{Error}");
        return $Self->ExitCodeError();
    }
    $Self->Print( $Result->{Content} );
    return $Self->ExitCodeOk();
}
1;
