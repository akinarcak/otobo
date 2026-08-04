#!/usr/bin/env perl
# --
# D724 ESM is an enterprise service management platform based on CareOnCloud ESM.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --

use v5.24;
use strict;
use warnings;

use Kernel::System::ObjectManager;

die "D724_DEMO_CUSTOMER_PASSWORD is required\n" if !length( $ENV{D724_DEMO_CUSTOMER_PASSWORD} // q{} );

local $Kernel::OM = Kernel::System::ObjectManager->new();
my $TenantID = 'd724-demo';
my $Login    = 'demo.customer';
my $UserID   = 1;

my $CompanyObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');
my %Company = $CompanyObject->CustomerCompanyGet( CustomerID => $TenantID );
if (!%Company) {
    my $Created = $CompanyObject->CustomerCompanyAdd(
        CustomerID             => $TenantID,
        CustomerCompanyName    => 'D724 Demo Company',
        CustomerCompanyStreet  => 'Private test environment',
        CustomerCompanyZIP     => '00000',
        CustomerCompanyCity    => 'Istanbul',
        CustomerCompanyCountry => 'Turkey',
        CustomerCompanyURL     => 'https://example.invalid',
        CustomerCompanyComment => 'D724 isolated demo tenant',
        ValidID                => 1,
        UserID                 => $UserID,
    );
    die "Could not create demo customer company\n" if !$Created;
}

my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');
my %CustomerUser = $CustomerUserObject->CustomerUserDataGet( User => $Login );
if (!%CustomerUser) {
    $Kernel::OM->Get('Kernel::Config')->Set( Key => 'CheckEmailAddresses', Value => 0 );
    my $Created = $CustomerUserObject->CustomerUserAdd(
        Source         => 'CustomerUser',
        UserFirstname  => 'D724',
        UserLastname   => 'Demo Customer',
        UserCustomerID => $TenantID,
        UserLogin      => $Login,
        UserEmail      => 'demo.customer@example.com',
        ValidID        => 1,
        UserID         => $UserID,
    );
    die "Could not create demo customer user\n" if !$Created;
}
die "Could not set demo customer password\n" if !$CustomerUserObject->SetPassword(
    UserLogin => $Login,
    PW        => $ENV{D724_DEMO_CUSTOMER_PASSWORD},
);

my $Catalog = $Kernel::OM->Get('Kernel::System::D724::Catalog');
my $Subject = { ID => 'demo-seeder', Roles => ['tenant_admin'], TenantIDs => [$TenantID] };
my %Write   = ( Subject => $Subject, TenantID => $TenantID, UserID => $UserID );
my $Commitment = eval { $Kernel::OM->Get('Kernel::System::D724::Commitment') };
if ($Commitment) {
    my $Policies = $Commitment->PolicyList( Subject => $Subject, TenantID => $TenantID );
    die "Could not list demo commitment policies\n" if !$Policies->{Success};
    my ($Policy) = grep { $_->{Key} eq 'standard-resolution' } @{ $Policies->{Data} };
    my $StandardObjectives = [
        { key => 'first-response', type => 'response', target_seconds => 3600, warning_percent => 75, start_signal => 'request_created', stop_signal => 'first_response', escalation_actions => [ { key => 'warn-owner', trigger => 'warning', type => 'notify_role', target => 'service_owner' } ] },
        { key => 'resolution', type => 'resolution', target_seconds => 28_800, warning_percent => 75, start_signal => 'request_created', stop_signal => 'request_fulfilled', escalation_actions => [ { key => 'assign-breach', trigger => 'breached', type => 'assignment', target => 'resolver-escalation' } ] },
        { key => 'internal-ola', type => 'ola', target_seconds => 14_400, warning_percent => 75, start_signal => 'request_approved', stop_signal => 'request_fulfilled', escalation_actions => [] },
    ];
    if (!$Policy) {
        my $Result = $Commitment->PolicyCreate(
            %Write, Key => 'standard-resolution', Name => 'Standard Request Resolution',
            CalendarID => 0, TargetSeconds => 28_800, WarningPercent => 75,
            PauseStatuses => ['awaiting_approval'], Status => 'active', Objectives => $StandardObjectives,
        );
        die "Could not create demo commitment policy: $Result->{Error}\n" if !$Result->{Success};
    }
    elsif ( !@{ $Policy->{Objectives} // [] } ) {
        my $Result = $Commitment->PolicyUpdate(
            %Write, PolicyID => $Policy->{PolicyID}, ExpectedVersion => $Policy->{Version}, Objectives => $StandardObjectives,
        );
        die "Could not upgrade demo commitment policy: $Result->{Error}\n" if !$Result->{Success};
    }
    my ($Premium) = grep { $_->{Key} eq 'developer-premium' } @{ $Policies->{Data} };
    if (!$Premium) {
        my $Result = $Commitment->PolicyCreate(
            %Write, Key => 'developer-premium', Name => 'Developer Premium', CalendarID => 0,
            TargetSeconds => 14_400, WarningPercent => 75, PauseStatuses => ['awaiting_approval'], Status => 'active',
            Objectives => [
                { key => 'first-response', type => 'response', target_seconds => 1800, warning_percent => 75, start_signal => 'request_created', stop_signal => 'first_response', escalation_actions => [ { key => 'warn-owner', trigger => 'warning', type => 'notify_role', target => 'service_owner' } ] },
                { key => 'resolution', type => 'resolution', target_seconds => 14_400, warning_percent => 75, start_signal => 'request_created', stop_signal => 'request_fulfilled', escalation_actions => [ { key => 'assign-breach', trigger => 'breached', type => 'assignment', target => 'developer-escalation' } ] },
                { key => 'internal-ola', type => 'ola', target_seconds => 7200, warning_percent => 75, start_signal => 'request_approved', stop_signal => 'request_fulfilled', escalation_actions => [] },
            ],
        );
        die "Could not create premium demo commitment policy: $Result->{Error}\n" if !$Result->{Success};
    }
}
my $Services = $Catalog->ServiceList( Subject => $Subject, TenantID => $TenantID );
die "Could not list demo services\n" if !$Services->{Success};
my ($Service) = grep { $_->{Key} eq 'digital-workplace' } @{ $Services->{Data} };
if (!$Service) {
    my $Result = $Catalog->ServiceCreate(
        %Write, Key => 'digital-workplace', Name => 'Digital Workplace',
        Description => 'Devices and workplace services for employees.', Status => 'active',
    );
    die "Could not create demo service: $Result->{Error}\n" if !$Result->{Success};
    $Service = $Result->{Data};
}
my $Offerings = $Catalog->OfferingList(
    Subject => $Subject, TenantID => $TenantID, ServiceID => $Service->{ServiceID},
);
die "Could not list demo offerings\n" if !$Offerings->{Success};
my ($Offering) = grep { $_->{Key} eq 'employee-device' } @{ $Offerings->{Data} };
if (!$Offering) {
    my $Result = $Catalog->OfferingCreate(
        %Write, ServiceID => $Service->{ServiceID}, Key => 'employee-device', Name => 'Employee Device',
        Description => 'Standard managed device fulfillment.', Status => 'active', FulfillmentType => 'process',
    );
    die "Could not create demo offering: $Result->{Error}\n" if !$Result->{Success};
    $Offering = $Result->{Data};
}
my $Items = $Catalog->CatalogItemList(
    Subject => $Subject, TenantID => $TenantID, OfferingID => $Offering->{OfferingID},
);
die "Could not list demo catalog items\n" if !$Items->{Success};
my ($Item) = grep { $_->{Key} eq 'request-laptop' } @{ $Items->{Data} };
if (!$Item) {
    my $Result = $Catalog->CatalogItemCreate(
        %Write, OfferingID => $Offering->{OfferingID}, Key => 'request-laptop', Name => 'Request a Laptop',
        Description => 'Request a managed laptop for an employee.', Status => 'active', RequestType => 'service_request',
    );
    die "Could not create demo item: $Result->{Error}\n" if !$Result->{Success};
    $Item = $Result->{Data};
}
my $ExistingSchema = $Catalog->CatalogItemSchemaGet(
    Subject => $Subject, TenantID => $TenantID, CatalogItemID => $Item->{CatalogItemID},
);
my $DesiredWorkflow = {
    approval => { required => 1, approver_role => 'tenant_admin' },
    fulfillment => [ { key => 'prepare', name => 'Prepare and deliver laptop', type => 'manual' } ],
    commitment => {
        default_policy_key => 'standard-resolution',
        entitlements => [ { key => 'developer-tier', answer_key => 'device_profile', equals => 'developer', policy_key => 'developer-premium' } ],
    },
};
if (!$ExistingSchema->{Success}) {
    my $Result = $Catalog->CatalogItemSchemaSet(
        %Write,
        CatalogItemID => $Item->{CatalogItemID},
        Schema => {
            version => 1,
            workflow => $DesiredWorkflow,
            fields  => [
                { key => 'employee', label => 'Employee', type => 'text', required => 1 },
                {
                    key => 'device_profile', label => 'Device profile', type => 'select', required => 1,
                    options => [
                        { value => 'standard', label => 'Standard office' },
                        { value => 'developer', label => 'Developer workstation' },
                    ],
                },
                { key => 'justification', label => 'Business justification', type => 'textarea', required => 1 },
            ],
        },
    );
    die "Could not create demo schema: $Result->{Error}\n" if !$Result->{Success};
}
elsif ( !( $ExistingSchema->{Data}->{Schema}->{workflow}->{commitment}->{default_policy_key} // q{} ) ) {
    my $Schema = $ExistingSchema->{Data}->{Schema};
    $Schema->{version}++;
    $Schema->{workflow} = $DesiredWorkflow;
    my $Result = $Catalog->CatalogItemSchemaSet(
        %Write, CatalogItemID => $Item->{CatalogItemID},
        ExpectedVersion => $ExistingSchema->{Data}->{Version}, Schema => $Schema,
    );
    die "Could not upgrade demo schema: $Result->{Error}\n" if !$Result->{Success};
}

say "D724 demo catalog and commitment policy seeded for tenant $TenantID and customer login $Login.";
