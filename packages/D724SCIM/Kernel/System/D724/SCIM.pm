# --
# CareOnCloud ESM enterprise service management platform.
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::SCIM;

use v5.24;
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

our $VERSION = '0.2.0';
our @ObjectDependencies = (
    'Kernel::Config', 'Kernel::System::D724::APIAuth', 'Kernel::System::D724::Audit',
    'Kernel::System::DB', 'Kernel::System::Main', 'Kernel::System::User',
    'Kernel::System::CustomerUser', 'Kernel::System::Valid',
);

my %ValidSurface = map { $_ => 1 } qw(agent customer);
my %ValidRole    = map { $_ => 1 } qw(requester agent service_owner auditor automation tenant_admin);

sub new { return bless {}, $_[0] }

sub UserCreate {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $V = $Self->_UserValidate(%Param); return $V if !$V->{Success};
    my $TenantID = $Param{TenantID};
    return $Self->_Error('USER_NAME_CONFLICT') if $Self->_UserByName( TenantID => $TenantID, UserName => $Param{UserName} );
    return $Self->_Error('EXTERNAL_ID_CONFLICT')
        if length( $Param{ExternalID} // q{} ) && $Self->_UserByExternal( TenantID => $TenantID, ExternalID => $Param{ExternalID} );
    return $Self->_Error('NATIVE_LOGIN_CONFLICT') if $Self->_NativeLoginExists(%Param);

    my $SCIMID = $Self->_IDGenerate( $TenantID, 'user', $Param{UserName} );
    my $Active = exists $Param{Active} ? ( $Param{Active} ? 1 : 0 ) : 1;
    my $Result = $Self->_TransactionRun( Code => sub {
        my ( $NativeUserID, $CustomerLogin );
        if ( $Param{Surface} eq 'agent' ) {
            $NativeUserID = $Kernel::OM->Get('Kernel::System::User')->UserAdd(
                UserFirstname => $Param{GivenName}, UserLastname => $Param{FamilyName},
                UserLogin => $Param{UserName}, UserEmail => $Param{Email},
                ValidID => $Self->_ValidID($Active), ChangeUserID => 1,
            );
            die "NATIVE_USER_CREATE_FAILED\n" if !$NativeUserID;
        }
        else {
            die "CUSTOMER_COMPANY_NOT_FOUND\n" if !$Self->_CustomerCompanyExists($TenantID);
            $CustomerLogin = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserAdd(
                UserFirstname => $Param{GivenName}, UserLastname => $Param{FamilyName},
                UserCustomerID => $TenantID, UserLogin => $Param{UserName}, UserEmail => $Param{Email},
                ValidID => $Self->_ValidID($Active), UserID => 1,
            );
            die "NATIVE_USER_CREATE_FAILED\n" if !$CustomerLogin;
        }
        my @Values = (
            $SCIMID, $TenantID, $Param{ExternalID} // undef, $Param{Surface}, $Param{UserName},
            $Param{Email}, $Param{GivenName}, $Param{FamilyName}, $Active, $NativeUserID, $CustomerLogin,
        );
        my @Bind = map { \$_ } @Values;
        die "SCIM_USER_INSERT_FAILED\n" if !$Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL => 'INSERT INTO d724_scim_user (scim_id, tenant_id, external_id, surface, user_name, email, given_name, family_name, active, native_user_id, customer_login, version, create_time, change_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, current_timestamp, current_timestamp)',
            Bind => \@Bind,
        );
        $Self->_MembershipSet( TenantID => $TenantID, NativeUserID => $NativeUserID, Role => 'requester', Active => $Active )
            if $Param{Surface} eq 'agent';
        $Self->_Audit( Auth => $Auth, TenantID => $TenantID, Action => 'scim.user.created',
            ObjectType => 'scim_user', ObjectID => $SCIMID, Version => 1, From => q{}, To => $Active ? 'active' : 'inactive',
            Details => { surface => $Param{Surface}, user_name => $Param{UserName} } );
        return $Self->_UserByID( TenantID => $TenantID, SCIMID => $SCIMID );
    } );
    return $Result if !$Result->{Success};
    return { Success => 1, Data => $Self->_UserResource( $Result->{Data} ) };
}

sub UserGet {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    return $Self->_Error('ID_INVALID') if !$Self->_IDValid( $Param{SCIMID} );
    my $Row = $Self->_UserByID(%Param); return $Self->_Error('NOT_FOUND') if !$Row;
    return { Success => 1, Data => $Self->_UserResource($Row) };
}

sub UserList {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $Start = $Param{StartIndex} // 1; my $Count = $Param{Count} // 100;
    my $Max = $Kernel::OM->Get('Kernel::Config')->Get('D724::SCIM::ListLimitMax') // 200;
    return $Self->_Error('PAGINATION_INVALID') if $Start !~ m{\A[1-9][0-9]*\z}smx || $Count !~ m{\A[1-9][0-9]*\z}smx || $Count > $Max;
    my ( $Where, @Values ) = ( 'tenant_id = ?', $Param{TenantID} );
    if ( defined $Param{FilterAttribute} ) {
        return $Self->_Error('FILTER_UNSUPPORTED') if ( $Param{FilterAttribute} // q{} ) !~ m{\A(?:id|userName|externalId)\z}smx || ( $Param{FilterOperator} // q{} ) ne 'eq';
        return $Self->_Error('FILTER_VALUE_INVALID') if !length( $Param{FilterValue} // q{} ) || length $Param{FilterValue} > 255;
        my %Column = ( id => 'scim_id', userName => 'user_name', externalId => 'external_id' );
        $Where .= " AND $Column{$Param{FilterAttribute}} = ?"; push @Values, $Param{FilterValue};
    }
    my $DB = $Kernel::OM->Get('Kernel::System::DB'); my @Bind = map { \$_ } @Values;
    $DB->Prepare( SQL => "SELECT COUNT(*) FROM d724_scim_user WHERE $Where", Bind => \@Bind ); my ($Total) = $DB->FetchrowArray();
    $DB->Prepare(
        SQL => "SELECT scim_id, tenant_id, external_id, surface, user_name, email, given_name, family_name, active, native_user_id, customer_login, version, create_time, change_time FROM d724_scim_user WHERE $Where ORDER BY scim_id",
        Bind => \@Bind, Limit => $Count, Offset => $Start - 1,
    );
    my @Resources; while ( my @R = $DB->FetchrowArray() ) { push @Resources, $Self->_UserResource( $Self->_UserRow(\@R) ) }
    return { Success => 1, Data => { totalResults => 0 + ($Total // 0), startIndex => 0 + $Start, itemsPerPage => scalar @Resources, Resources => \@Resources } };
}

sub UserReplace {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    return $Self->_Error('ID_INVALID') if !$Self->_IDValid( $Param{SCIMID} );
    my $Current = $Self->_UserByID(%Param); return $Self->_Error('NOT_FOUND') if !$Current;
    return $Self->_Error('VERSION_REQUIRED') if ( $Param{ExpectedVersion} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    return $Self->_Error('VERSION_CONFLICT') if $Current->{Version} != $Param{ExpectedVersion};
    return $Self->_Error('IMMUTABLE_ATTRIBUTE') if defined $Param{UserName} && $Param{UserName} ne $Current->{UserName};
    return $Self->_Error('IMMUTABLE_ATTRIBUTE') if defined $Param{ExternalID} && ($Param{ExternalID} // q{}) ne ($Current->{ExternalID} // q{});
    for my $Key (qw(Email GivenName FamilyName)) { $Param{$Key} = $Current->{$Key} if !defined $Param{$Key} }
    $Param{Surface} = $Current->{Surface}; $Param{UserName} = $Current->{UserName};
    my $V = $Self->_UserValidate(%Param); return $V if !$V->{Success};
    my $Active = exists $Param{Active} ? ( $Param{Active} ? 1 : 0 ) : $Current->{Active};
    my $Next = $Current->{Version} + 1;
    my $Result = $Self->_TransactionRun( Code => sub {
        my $NativeActive = $Active;
        if ( $Current->{Surface} eq 'agent' ) {
            $Self->_UserMembershipsReconcile( TenantID => $Param{TenantID}, User => $Current, Active => $Active );
            $NativeActive = 1 if !$Active && $Self->_AgentHasActiveMembership( NativeUserID => $Current->{NativeUserID} );
        }
        $Self->_NativeUserUpdate( Row => $Current, %Param, Active => $NativeActive );
        my @Values = ( $Param{Email}, $Param{GivenName}, $Param{FamilyName}, $Active, $Param{TenantID}, $Param{SCIMID}, $Current->{Version} );
        my @Bind = map { \$_ } @Values;
        die "VERSION_CONFLICT\n" if !$Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL => 'UPDATE d724_scim_user SET email = ?, given_name = ?, family_name = ?, active = ?, version = version + 1, change_time = current_timestamp WHERE tenant_id = ? AND scim_id = ? AND version = ?', Bind => \@Bind,
        );
        my $Updated=$Self->_UserByID(%Param);die "VERSION_CONFLICT\n" if!$Updated||$Updated->{Version}!=$Next;
        $Self->_Audit( Auth => $Auth, TenantID => $Param{TenantID}, Action => 'scim.user.updated', ObjectType => 'scim_user', ObjectID => $Param{SCIMID}, Version => $Next,
            From => $Current->{Active} ? 'active' : 'inactive', To => $Active ? 'active' : 'inactive', Details => { surface => $Current->{Surface}, user_name => $Current->{UserName} } );
        return $Self->_UserByID(%Param);
    } );
    return $Result if !$Result->{Success};
    return { Success => 1, Data => $Self->_UserResource( $Result->{Data} ) };
}

sub UserDelete {
    my ( $Self, %Param ) = @_;
    return $Self->UserReplace( %Param, Active => 0 );
}

sub GroupCreate {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $V = $Self->_GroupValidate(%Param); return $V if !$V->{Success};
    return $Self->_Error('GROUP_CONFLICT') if $Self->_GroupByName(%Param);
    my $ID = $Self->_IDGenerate( $Param{TenantID}, 'group', $Param{DisplayName} );
    my $Result = $Self->_TransactionRun( Code => sub {
        my @Values = ( $ID, $Param{TenantID}, $Param{ExternalID} // undef, $Param{DisplayName}, $Param{Role} ); my @Bind = map { \$_ } @Values;
        die "SCIM_GROUP_INSERT_FAILED\n" if !$Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL => 'INSERT INTO d724_scim_group (scim_id, tenant_id, external_id, display_name, role_name, version, create_time, change_time) VALUES (?, ?, ?, ?, ?, 1, current_timestamp, current_timestamp)', Bind => \@Bind,
        );
        $Self->_GroupMembersReplace( TenantID => $Param{TenantID}, GroupID => $ID, Role => $Param{Role}, Members => $Param{Members} // [] );
        $Self->_Audit( Auth => $Auth, TenantID => $Param{TenantID}, Action => 'scim.group.created', ObjectType => 'scim_group', ObjectID => $ID, Version => 1, From => q{}, To => 'active', Details => { role => $Param{Role}, display_name => $Param{DisplayName} } );
        return $Self->_GroupByID( TenantID => $Param{TenantID}, SCIMID => $ID );
    } );
    return $Result if !$Result->{Success}; return { Success => 1, Data => $Self->_GroupResource( $Result->{Data} ) };
}

sub GroupGet {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $Row = $Self->_GroupByID(%Param); return $Self->_Error('NOT_FOUND') if !$Row;
    return { Success => 1, Data => $Self->_GroupResource($Row) };
}

sub GroupList {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $Start = $Param{StartIndex} // 1; my $Count = $Param{Count} // 100;
    my $Max = $Kernel::OM->Get('Kernel::Config')->Get('D724::SCIM::ListLimitMax') // 200;
    return $Self->_Error('PAGINATION_INVALID') if $Start !~ m{\A[1-9][0-9]*\z}smx || $Count !~ m{\A[1-9][0-9]*\z}smx || $Count > $Max;
    my ( $Where, @Values ) = ( 'tenant_id = ?', $Param{TenantID} );
    if ( defined $Param{FilterAttribute} ) {
        return $Self->_Error('FILTER_UNSUPPORTED') if ( $Param{FilterAttribute} // q{} ) !~ m{\A(?:id|displayName|externalId)\z}smx || ( $Param{FilterOperator} // q{} ) ne 'eq';
        return $Self->_Error('FILTER_VALUE_INVALID') if !length( $Param{FilterValue} // q{} ) || length $Param{FilterValue} > 255;
        my %Column = ( id => 'scim_id', displayName => 'display_name', externalId => 'external_id' );
        $Where .= " AND $Column{$Param{FilterAttribute}} = ?"; push @Values, $Param{FilterValue};
    }
    my $DB = $Kernel::OM->Get('Kernel::System::DB'); my @Bind = map { \$_ } @Values;
    $DB->Prepare( SQL => "SELECT COUNT(*) FROM d724_scim_group WHERE $Where", Bind => \@Bind ); my ($Total) = $DB->FetchrowArray();
    $DB->Prepare( SQL => "SELECT scim_id,tenant_id,external_id,display_name,role_name,version,create_time,change_time FROM d724_scim_group WHERE $Where ORDER BY scim_id", Bind => \@Bind, Limit => $Count, Offset => $Start - 1 );
    my @Resources; while ( my @R = $DB->FetchrowArray() ) { push @Resources, $Self->_GroupResource({SCIMID=>$R[0],TenantID=>$R[1],ExternalID=>$R[2],DisplayName=>$R[3],Role=>$R[4],Version=>0+$R[5],CreateTime=>$R[6],ChangeTime=>$R[7]}) }
    return { Success => 1, Data => { totalResults => 0 + ($Total // 0), startIndex => 0 + $Start, itemsPerPage => scalar @Resources, Resources => \@Resources } };
}

sub GroupReplace {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $Current = $Self->_GroupByID(%Param); return $Self->_Error('NOT_FOUND') if !$Current;
    return $Self->_Error('VERSION_REQUIRED') if ( $Param{ExpectedVersion} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    return $Self->_Error('VERSION_CONFLICT') if $Current->{Version} != $Param{ExpectedVersion};
    return $Self->_Error('IMMUTABLE_ATTRIBUTE') if defined $Param{ExternalID} && ($Param{ExternalID} // q{}) ne ($Current->{ExternalID} // q{});
    $Param{DisplayName} //= $Current->{DisplayName}; $Param{Role} //= $Current->{Role};
    my $V = $Self->_GroupValidate(%Param); return $V if !$V->{Success};
    my $Next = $Current->{Version} + 1;
    my $Result = $Self->_TransactionRun( Code => sub {
        my @Values = ( $Param{DisplayName}, $Param{Role}, $Param{TenantID}, $Param{SCIMID}, $Current->{Version} ); my @Bind = map { \$_ } @Values;
        die "VERSION_CONFLICT\n" if !$Kernel::OM->Get('Kernel::System::DB')->Do( SQL => 'UPDATE d724_scim_group SET display_name = ?, role_name = ?, version = version + 1, change_time = current_timestamp WHERE tenant_id = ? AND scim_id = ? AND version = ?', Bind => \@Bind );
        my $Updated=$Self->_GroupByID(%Param);die "VERSION_CONFLICT\n" if!$Updated||$Updated->{Version}!=$Next;
        $Self->_GroupMembersReplace( TenantID => $Param{TenantID}, GroupID => $Param{SCIMID}, Role => $Param{Role}, Members => $Param{Members} // [] );
        if ( $Param{Role} ne $Current->{Role} ) {
            for my $MemberID ( @{ $Param{Members} // [] } ) {
                my $User = $Self->_UserByID( TenantID => $Param{TenantID}, SCIMID => $MemberID );
                $Self->_RoleReconcile( TenantID => $Param{TenantID}, User => $User, Role => $Current->{Role} ) if $User;
            }
        }
        $Self->_Audit( Auth => $Auth, TenantID => $Param{TenantID}, Action => 'scim.group.updated', ObjectType => 'scim_group', ObjectID => $Param{SCIMID}, Version => $Next, From => 'active', To => 'active', Details => { role => $Param{Role}, display_name => $Param{DisplayName} } );
        return $Self->_GroupByID(%Param);
    } );
    return $Result if !$Result->{Success}; return { Success => 1, Data => $Self->_GroupResource( $Result->{Data} ) };
}

sub GroupDelete {
    my ( $Self, %Param ) = @_;
    my $Auth = $Self->_Authorize(%Param); return $Auth if !$Auth->{Success};
    my $Current = $Self->_GroupByID(%Param); return $Self->_Error('NOT_FOUND') if !$Current;
    return $Self->_Error('VERSION_REQUIRED') if ( $Param{ExpectedVersion} // q{} ) !~ m{\A[1-9][0-9]*\z}smx;
    return $Self->_Error('VERSION_CONFLICT') if $Current->{Version} != $Param{ExpectedVersion};
    my $Result = $Self->_TransactionRun( Code => sub {
        my $T=$Param{TenantID};my $G=$Param{SCIMID};my $DB=$Kernel::OM->Get('Kernel::System::DB');
        $DB->Prepare(SQL=>'SELECT user_id FROM d724_scim_group_member WHERE tenant_id = ? AND group_id = ?',Bind=>[\$T,\$G]);my @IDs;while(my($ID)=$DB->FetchrowArray()){push @IDs,$ID}
        $DB->Do(SQL=>'DELETE FROM d724_scim_group_member WHERE tenant_id = ? AND group_id = ?',Bind=>[\$T,\$G]) || die "MEMBER_DELETE_FAILED\n";
        $DB->Do(SQL=>'DELETE FROM d724_scim_group WHERE tenant_id = ? AND scim_id = ? AND version = ?',Bind=>[\$T,\$G,\$Current->{Version}]) || die "VERSION_CONFLICT\n";
        die "VERSION_CONFLICT\n" if $Self->_GroupByID(%Param);
        for my $ID(@IDs){my $U=$Self->_UserByID(TenantID=>$T,SCIMID=>$ID);$Self->_RoleReconcile(TenantID=>$T,User=>$U,Role=>$Current->{Role})if$U}
        $Self->_Audit(Auth=>$Auth,TenantID=>$T,Action=>'scim.group.deleted',ObjectType=>'scim_group',ObjectID=>$G,Version=>$Current->{Version}+1,From=>'active',To=>'deleted',Details=>{role=>$Current->{Role},display_name=>$Current->{DisplayName}});
        return 1;
    });
    return $Result if !$Result->{Success}; return { Success => 1 };
}

sub _Authorize {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('SCIM_DISABLED') if !$Kernel::OM->Get('Kernel::Config')->Get('D724::SCIM::Enabled');
    return $Self->_Error('TENANT_ID_INVALID') if ( $Param{TenantID} // q{} ) !~ m{\A[a-z0-9][a-z0-9_-]{1,127}\z}smx;
    return $Kernel::OM->Get('Kernel::System::D724::APIAuth')->Authorize( AccessToken => $Param{AccessToken}, TenantID => $Param{TenantID}, Action => 'scim.provision' );
}

sub _UserValidate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('SURFACE_INVALID') if !$ValidSurface{ $Param{Surface} // q{} };
    return $Self->_Error('USER_NAME_INVALID') if ( $Param{UserName} // q{} ) !~ m{\A[^\x00-\x20]{3,200}\z}smx;
    return $Self->_Error('EMAIL_INVALID') if ( $Param{Email} // q{} ) !~ m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z}smx || length $Param{Email} > 255;
    for my $Key (qw(GivenName FamilyName)) { return $Self->_Error( uc($Key) . '_INVALID' ) if !length( $Param{$Key} // q{} ) || length $Param{$Key} > 100 || $Param{$Key} =~ m{[\x00-\x1f]}smx }
    return $Self->_Error('EXTERNAL_ID_INVALID') if length( $Param{ExternalID} // q{} ) > 255 || ( $Param{ExternalID} // q{} ) =~ m{[\x00-\x1f]}smx;
    return { Success => 1 };
}

sub _GroupValidate {
    my ( $Self, %Param ) = @_;
    return $Self->_Error('DISPLAY_NAME_INVALID') if !length( $Param{DisplayName} // q{} ) || length $Param{DisplayName} > 200 || $Param{DisplayName} =~ m{[\x00-\x1f]}smx;
    return $Self->_Error('ROLE_INVALID') if !$ValidRole{ $Param{Role} // q{} };
    return $Self->_Error('MEMBERS_INVALID') if defined $Param{Members} && ( ref $Param{Members} ne 'ARRAY' || @{ $Param{Members} } > 1000 );
    for my $ID ( @{ $Param{Members} // [] } ) { return $Self->_Error('MEMBER_ID_INVALID') if !$Self->_IDValid($ID) }
    return { Success => 1 };
}

sub _NativeLoginExists {
    my ( $Self, %Param ) = @_;
    return $Kernel::OM->Get('Kernel::System::User')->UserLoginExistsCheck( UserLogin => $Param{UserName} ) if $Param{Surface} eq 'agent';
    my %User = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet( User => $Param{UserName} ); return %User ? 1 : 0;
}

sub _NativeUserUpdate {
    my ( $Self, %Param ) = @_; my $R = $Param{Row};
    my $OK;
    if ( $R->{Surface} eq 'agent' ) {
        $OK = $Kernel::OM->Get('Kernel::System::User')->UserUpdate( UserID => $R->{NativeUserID}, UserFirstname => $Param{GivenName}, UserLastname => $Param{FamilyName}, UserLogin => $R->{UserName}, UserEmail => $Param{Email}, ValidID => $Self->_ValidID($Param{Active}), ChangeUserID => 1 );
    }
    else {
        $OK = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserUpdate( ID => $R->{CustomerLogin}, UserLogin => $R->{UserName}, UserFirstname => $Param{GivenName}, UserLastname => $Param{FamilyName}, UserCustomerID => $Param{TenantID}, UserEmail => $Param{Email}, ValidID => $Self->_ValidID($Param{Active}), UserID => 1 );
    }
    die "NATIVE_USER_UPDATE_FAILED\n" if !$OK;
    return 1;
}

sub _GroupMembersReplace {
    my ( $Self, %Param ) = @_; my %Wanted = map { $_ => 1 } @{ $Param{Members} };
    my $DB = $Kernel::OM->Get('Kernel::System::DB'); my ( $Tenant, $Group ) = @Param{qw(TenantID GroupID)};
    $DB->Prepare( SQL => 'SELECT user_id FROM d724_scim_group_member WHERE tenant_id = ? AND group_id = ?', Bind => [ \$Tenant, \$Group ] );
    my %Current; while ( my ($ID) = $DB->FetchrowArray() ) { $Current{$ID} = 1 }
    for my $ID ( keys %Wanted ) {
        my $User = $Self->_UserByID( TenantID => $Tenant, SCIMID => $ID ); die "MEMBER_NOT_FOUND\n" if !$User || $User->{Surface} ne 'agent';
        if ( !$Current{$ID} ) { $DB->Do( SQL => 'INSERT INTO d724_scim_group_member (group_id, user_id, tenant_id, create_time) VALUES (?, ?, ?, current_timestamp)', Bind => [ \$Group, \$ID, \$Tenant ] ) || die "MEMBER_INSERT_FAILED\n" }
        $Self->_MembershipSet( TenantID => $Tenant, NativeUserID => $User->{NativeUserID}, Role => $Param{Role}, Active => $User->{Active} );
    }
    for my $ID ( keys %Current ) {
        next if $Wanted{$ID}; my $User = $Self->_UserByID( TenantID => $Tenant, SCIMID => $ID );
        $DB->Do( SQL => 'DELETE FROM d724_scim_group_member WHERE tenant_id = ? AND group_id = ? AND user_id = ?', Bind => [ \$Tenant, \$Group, \$ID ] ) || die "MEMBER_DELETE_FAILED\n";
        $Self->_RoleReconcile( TenantID => $Tenant, User => $User, Role => $Param{Role} ) if $User;
    }
    return 1;
}

sub _RoleReconcile {
    my ( $Self, %Param ) = @_; my ($Tenant,$User,$Role)=@Param{qw(TenantID User Role)}; my $DB=$Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare( SQL => 'SELECT 1 FROM d724_scim_group_member m INNER JOIN d724_scim_group g ON g.scim_id = m.group_id AND g.tenant_id = m.tenant_id WHERE m.tenant_id = ? AND m.user_id = ? AND g.role_name = ?', Bind => [ \$Tenant, \$User->{SCIMID}, \$Role ], Limit => 1 ); my ($Keep)=$DB->FetchrowArray();
    $Self->_MembershipSet( TenantID => $Tenant, NativeUserID => $User->{NativeUserID}, Role => $Role, Active => $Keep ? 1 : 0 ); return 1;
}

sub _MembershipSet {
    my ( $Self, %Param ) = @_; return 1 if !$Param{NativeUserID}; my $DB=$Kernel::OM->Get('Kernel::System::DB'); my ($T,$U,$R)=@Param{qw(TenantID NativeUserID Role)};
    $DB->Prepare( SQL => 'SELECT id, status FROM d724_tenant_agent_role WHERE tenant_id = ? AND user_id = ? AND role_name = ? FOR UPDATE', Bind => [ \$T, \$U, \$R ] ); my ($ID,$Status)=$DB->FetchrowArray(); my $Want=$Param{Active}?'active':'revoked';
    return 1 if $ID && $Status eq $Want;
    if ($ID) { $DB->Do( SQL => 'UPDATE d724_tenant_agent_role SET status = ?, version = version + 1, change_time = current_timestamp, change_by = 1 WHERE id = ?', Bind => [ \$Want, \$ID ] ) || die "MEMBERSHIP_UPDATE_FAILED\n" }
    elsif ($Param{Active}) { $DB->Do( SQL => "INSERT INTO d724_tenant_agent_role (tenant_id,user_id,role_name,status,version,create_time,create_by,change_time,change_by) VALUES (?,?,?,'active',1,current_timestamp,1,current_timestamp,1)", Bind => [ \$T, \$U, \$R ] ) || die "MEMBERSHIP_INSERT_FAILED\n" }
    return 1;
}

sub _UserMembershipsReconcile {
    my ( $Self, %Param ) = @_; my $U=$Param{User}; return 1 if !$U->{NativeUserID};
    my $T=$Param{TenantID}; my $DB=$Kernel::OM->Get('Kernel::System::DB');
    if (!$Param{Active}) {
        $DB->Do( SQL => "UPDATE d724_tenant_agent_role SET status = 'revoked', version = version + 1, change_time = current_timestamp, change_by = 1 WHERE tenant_id = ? AND user_id = ? AND status = 'active'", Bind => [ \$T, \$U->{NativeUserID} ] ) || die "MEMBERSHIP_UPDATE_FAILED\n";
        return 1;
    }
    $Self->_MembershipSet(TenantID=>$T,NativeUserID=>$U->{NativeUserID},Role=>'requester',Active=>1);
    $DB->Prepare(SQL=>'SELECT DISTINCT g.role_name FROM d724_scim_group_member m INNER JOIN d724_scim_group g ON g.scim_id=m.group_id AND g.tenant_id=m.tenant_id WHERE m.tenant_id=? AND m.user_id=?',Bind=>[\$T,\$U->{SCIMID}]);
    while(my($Role)=$DB->FetchrowArray()){$Self->_MembershipSet(TenantID=>$T,NativeUserID=>$U->{NativeUserID},Role=>$Role,Active=>1)}
    return 1;
}

sub _AgentHasActiveMembership {
    my ( $Self, %Param ) = @_; my $U=$Param{NativeUserID}; my $DB=$Kernel::OM->Get('Kernel::System::DB');
    $DB->Prepare( SQL => "SELECT 1 FROM d724_tenant_agent_role WHERE user_id = ? AND status = 'active'", Bind => [ \$U ], Limit => 1 ); my ($Has)=$DB->FetchrowArray(); return 1 if $Has;
    return 0;
}

sub _UserByID { my ( $Self,%P)=@_; return if !$Self->_IDValid($P{SCIMID}); return $Self->_UserSelect('tenant_id = ? AND scim_id = ?', $P{TenantID}, $P{SCIMID}) }
sub _UserByName { my ( $Self,%P)=@_; return $Self->_UserSelect('tenant_id = ? AND user_name = ?', $P{TenantID}, $P{UserName}) }
sub _UserByExternal { my ( $Self,%P)=@_; return $Self->_UserSelect('tenant_id = ? AND external_id = ?', $P{TenantID}, $P{ExternalID}) }
sub _UserSelect { my ( $Self,$Where,@V)=@_; my @B=map{\$_}@V; my $DB=$Kernel::OM->Get('Kernel::System::DB'); $DB->Prepare(SQL=>"SELECT scim_id, tenant_id, external_id, surface, user_name, email, given_name, family_name, active, native_user_id, customer_login, version, create_time, change_time FROM d724_scim_user WHERE $Where",Bind=>\@B,Limit=>1); my @R=$DB->FetchrowArray(); return @R ? $Self->_UserRow(\@R) : undef }
sub _UserRow { my($Self,$R)=@_; return { SCIMID=>$R->[0],TenantID=>$R->[1],ExternalID=>$R->[2],Surface=>$R->[3],UserName=>$R->[4],Email=>$R->[5],GivenName=>$R->[6],FamilyName=>$R->[7],Active=>0+$R->[8],NativeUserID=>$R->[9],CustomerLogin=>$R->[10],Version=>0+$R->[11],CreateTime=>$R->[12],ChangeTime=>$R->[13] } }
sub _UserResource { my($Self,$R)=@_; return { schemas=>['urn:ietf:params:scim:schemas:core:2.0:User'],id=>$R->{SCIMID},externalId=>$R->{ExternalID},userName=>$R->{UserName},name=>{givenName=>$R->{GivenName},familyName=>$R->{FamilyName}},emails=>[{value=>$R->{Email},primary=>1,type=>'work'}],active=>$R->{Active}?1:0,'urn:careoncloud:params:scim:schemas:extension:esm:2.0:User'=>{surface=>$R->{Surface},tenantId=>$R->{TenantID}},meta=>{resourceType=>'User',created=>$R->{CreateTime},lastModified=>$R->{ChangeTime},version=>'W/"'.$R->{Version}.'"'} } }

sub _GroupByID { my($Self,%P)=@_; return if !$Self->_IDValid($P{SCIMID}); return $Self->_GroupSelect('tenant_id = ? AND scim_id = ?',$P{TenantID},$P{SCIMID}) }
sub _GroupByName { my($Self,%P)=@_; return $Self->_GroupSelect('tenant_id = ? AND display_name = ?',$P{TenantID},$P{DisplayName}) }
sub _GroupSelect { my($Self,$W,@V)=@_; my @B=map{\$_}@V; my $DB=$Kernel::OM->Get('Kernel::System::DB');$DB->Prepare(SQL=>"SELECT scim_id,tenant_id,external_id,display_name,role_name,version,create_time,change_time FROM d724_scim_group WHERE $W",Bind=>\@B,Limit=>1);my @R=$DB->FetchrowArray();return @R?{SCIMID=>$R[0],TenantID=>$R[1],ExternalID=>$R[2],DisplayName=>$R[3],Role=>$R[4],Version=>0+$R[5],CreateTime=>$R[6],ChangeTime=>$R[7]}:undef }
sub _GroupResource { my($Self,$R)=@_;my $T=$R->{TenantID};my $G=$R->{SCIMID};my $DB=$Kernel::OM->Get('Kernel::System::DB');$DB->Prepare(SQL=>'SELECT user_id FROM d724_scim_group_member WHERE tenant_id = ? AND group_id = ? ORDER BY user_id',Bind=>[\$T,\$G]);my @M;while(my($ID)=$DB->FetchrowArray()){push @M,{value=>$ID}}return {schemas=>['urn:ietf:params:scim:schemas:core:2.0:Group'],id=>$R->{SCIMID},externalId=>$R->{ExternalID},displayName=>$R->{DisplayName},members=>\@M,'urn:careoncloud:params:scim:schemas:extension:esm:2.0:Group'=>{role=>$R->{Role},tenantId=>$R->{TenantID}},meta=>{resourceType=>'Group',created=>$R->{CreateTime},lastModified=>$R->{ChangeTime},version=>'W/"'.$R->{Version}.'"'}} }

sub _CustomerCompanyExists { my($Self,$ID)=@_;my $DB=$Kernel::OM->Get('Kernel::System::DB');$DB->Prepare(SQL=>'SELECT 1 FROM customer_company WHERE customer_id = ?',Bind=>[\$ID],Limit=>1);my($OK)=$DB->FetchrowArray();return $OK }
sub _ValidID { my($Self,$Active)=@_;my $ID=$Kernel::OM->Get('Kernel::System::Valid')->ValidLookup(Valid=>$Active?'valid':'invalid');return $ID || ($Active?1:2) }
sub _IDGenerate { my($Self,@P)=@_;return substr(sha256_hex(join('|',@P,time(),$Kernel::OM->Get('Kernel::System::Main')->GenerateRandomString(Length=>32))),0,32) }
sub _IDValid { my($Self,$ID)=@_;return defined $ID && $ID =~ m{\A[a-f0-9]{32}\z}smx ? 1:0 }
sub _Audit { my($Self,%P)=@_;my $A=$P{Auth}->{Data};my $R=$Kernel::OM->Get('Kernel::System::D724::Audit')->Record(TenantID=>$P{TenantID},ActorType=>'integration',ActorID=>'integration:'.$A->{ClientID},Action=>$P{Action},ObjectType=>$P{ObjectType},ObjectID=>$P{ObjectID},CorrelationID=>'scim:'.$P{ObjectID},DedupeKey=>'scim:'.$P{ObjectID}.':version:'.$P{Version},FromState=>$P{From},ToState=>$P{To},Outcome=>'success',Details=>$P{Details});die "AUDIT_WRITE_FAILED\n" if !$R->{Success};return 1 }
sub _TransactionRun { my($Self,%P)=@_;my $DB=$Kernel::OM->Get('Kernel::System::DB');my $H=$DB->Connect();return $Self->_Error('DATABASE_UNAVAILABLE')if!$H;my $Own=$H->{AutoCommit}?1:0;my $Data;my $OK=eval{$DB->BeginWork()if$Own;$Data=$P{Code}->();$H->commit()if$Own;1};if(!$OK){my $E=$@||'TRANSACTION_FAILED';eval{$DB->Rollback()}if$Own;my($Code)=$E=~m{\A([A-Z0-9_]+)};return $Self->_Error($Code||'TRANSACTION_FAILED')}return {Success=>1,Data=>$Data} }
sub _Error { my($Self,$E,$R)=@_;return {Success=>0,Error=>$E,Reason=>$R//$E} }

1;
