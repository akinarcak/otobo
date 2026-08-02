#!/usr/bin/env perl
use strict;
use warnings;
use Kernel::System::UnitTest::RegisterOM;

my $DB = $Kernel::OM->Get('Kernel::System::DB');
my $Ticket = $Kernel::OM->Get('Kernel::System::Ticket');
my $TN = '2015071510123456';
my @Bind = ( \$TN );
$DB->Prepare( SQL => 'SELECT id FROM ticket WHERE tn = ?', Bind => \@Bind )
    or die "Could not find quick-setup ticket.\n";
my ($TicketID) = $DB->FetchrowArray();
exit 0 if !$TicketID;
$Ticket->{D724TicketAuditSuppress} = 1;
die "Could not delete quick-setup ticket $TicketID.\n"
    if !$Ticket->TicketDelete( TicketID => $TicketID, UserID => 1 );
print "Removed development quick-setup ticket $TicketID.\n";
exit 0;
