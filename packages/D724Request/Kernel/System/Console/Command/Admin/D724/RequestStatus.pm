# --
# D724 ESM is an enterprise service management platform based on OTOBO.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

package Kernel::System::Console::Command::Admin::D724::RequestStatus;

use v5.24;
use strict;
use warnings;
use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = ('Kernel::System::DB', 'Kernel::System::JSON');

sub Configure {
    my ($Self) = @_;
    $Self->Description('Validate the D724 request orchestration schema and print counts.');
    $Self->AddOption( Name => 'json', Description => 'Print JSON.', Required => 0, HasValue => 0 );
    return;
}

sub Run {
    my ($Self) = @_;
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    my %Existing = map { $_ => 1 } $DBObject->ListTables();
    my %Tables = map { $_ => $Existing{$_} ? 1 : 0 } qw(d724_request d724_request_approval d724_request_task);
    my %Counts = ( Requests => 0, PendingApprovals => 0, OpenTasks => 0 );
    if ( $Tables{d724_request} ) {
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_request WHERE status NOT IN ('initializing', 'submission_failed')" );
        ($Counts{Requests}) = $DBObject->FetchrowArray();
    }
    if ( $Tables{d724_request_approval} ) {
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_request_approval WHERE status = 'pending'" );
        ($Counts{PendingApprovals}) = $DBObject->FetchrowArray();
    }
    if ( $Tables{d724_request_task} ) {
        $DBObject->Prepare( SQL => "SELECT COUNT(*) FROM d724_request_task WHERE status IN ('blocked', 'pending', 'in_progress')" );
        ($Counts{OpenTasks}) = $DBObject->FetchrowArray();
    }
    my $Success = !( grep { !$_ } values %Tables );
    my $Status = { Success => $Success ? 1 : 0, Package => 'D724Request', Version => '0.2.1', Tables => \%Tables, Counts => \%Counts };
    if ( $Self->GetOption('json') ) {
        $Self->Print( $Kernel::OM->Get('Kernel::System::JSON')->Encode( Data => $Status, SortKeys => 1, Pretty => 1 ) );
    }
    else {
        $Self->Print("D724 request status\nRequests: $Counts{Requests}\nPending approvals: $Counts{PendingApprovals}\nOpen tasks: $Counts{OpenTasks}\n");
        $Self->Print( $Success ? "Status: OK\n" : "Status: FAILED\n" );
    }
    return $Success ? $Self->ExitCodeOk() : $Self->ExitCodeError();
}

1;
