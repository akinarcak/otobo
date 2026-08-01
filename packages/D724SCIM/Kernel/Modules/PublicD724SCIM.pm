# --
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::Modules::PublicD724SCIM;

use v5.24;
use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new { my ( $Type, %Param ) = @_; return bless \%Param, $Type }

sub Run {
    my ($Self) = @_;
    my $Output = eval { $Self->_Run() };
    if ($@) {
        $Kernel::OM->Get('Kernel::System::Log')->Log( Priority => 'error', Message => 'CareOnCloud SCIM transport failed before response completion.' );
        return $Self->_ErrorResponse( Code => 500, Error => 'INTERNAL_ERROR' );
    }
    return $Output;
}

sub _Run {
    my ($Self) = @_;
    my $Request = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $Route = $Request->GetParam( Param => 'Route' ) // q{};
    my $Method = uc( $Request->RequestMethod() // q{} );
    my $TenantID = $Request->Header('X-CareOnCloud-Tenant') // q{};
    my $Bearer = $Self->_Bearer();
    return $Self->_ErrorResponse( Code => 401, Error => 'TOKEN_INVALID' ) if !defined $Bearer;

    if ( $Route =~ m{\A(?:service_provider_config|schemas|resource_types)\z}smx ) {
        return $Self->_ErrorResponse( Code => 405, Error => 'METHOD_NOT_ALLOWED' ) if $Method ne 'GET';
        my $Auth = $Kernel::OM->Get('Kernel::System::D724::APIAuth')->Authorize( AccessToken => $Bearer, TenantID => $TenantID, Action => 'scim.provision' );
        return $Self->_Result( Result => $Auth ) if !$Auth->{Success};
        return $Self->_Discovery($Route);
    }

    my $SCIM = $Kernel::OM->Get('Kernel::System::D724::SCIM');
    my %Base = ( AccessToken => $Bearer, TenantID => $TenantID );
    if ( $Route eq 'users' && $Method eq 'GET' ) {
        my %Filter = $Self->_Filter(); return $Filter{Response} if $Filter{Response};
        return $Self->_Result( Result => $SCIM->UserList( %Base, StartIndex => $Request->GetParam(Param=>'startIndex') // 1, Count => $Request->GetParam(Param=>'count') // 100, %Filter ) );
    }
    if ( $Route eq 'users' && $Method eq 'POST' ) {
        my $P=$Self->_JSONPayload();return $P if ref $P ne 'HASH';my %U=$Self->_UserFields($P);
        return $Self->_Result( Result=>$SCIM->UserCreate(%Base,%U), SuccessCode=>201, ResourcePath=>'Users' );
    }
    if ( $Route eq 'user' && $Method eq 'GET' ) {
        return $Self->_Result( Result=>$SCIM->UserGet(%Base,SCIMID=>$Request->GetParam(Param=>'id')//q{}), ResourcePath=>'Users' );
    }
    if ( $Route eq 'user' && $Method eq 'PUT' ) {
        my $P=$Self->_JSONPayload();return $P if ref $P ne 'HASH';my $Version=$Self->_IfMatch();return $Version if ref $Version;
        return $Self->_Result( Result=>$SCIM->UserReplace(%Base,SCIMID=>$Request->GetParam(Param=>'id')//q{},ExpectedVersion=>$Version,$Self->_UserFields($P)), ResourcePath=>'Users' );
    }
    if ( $Route eq 'user' && $Method eq 'PATCH' ) {
        return $Self->_UserPatch( SCIM=>$SCIM, Base=>\%Base, ID=>$Request->GetParam(Param=>'id')//q{} );
    }
    if ( $Route eq 'user' && $Method eq 'DELETE' ) {
        my $Version=$Self->_IfMatch();return $Version if ref $Version;
        my $R=$SCIM->UserDelete(%Base,SCIMID=>$Request->GetParam(Param=>'id')//q{},ExpectedVersion=>$Version);
        return $Self->_Result(Result=>$R,SuccessCode=>204,NoContent=>1);
    }
    if ( $Route eq 'groups' && $Method eq 'GET' ) {
        my %Filter=$Self->_Filter();return $Filter{Response} if $Filter{Response};
        return $Self->_Result(Result=>$SCIM->GroupList(%Base,StartIndex=>$Request->GetParam(Param=>'startIndex')//1,Count=>$Request->GetParam(Param=>'count')//100,%Filter));
    }
    if ( $Route eq 'groups' && $Method eq 'POST' ) {
        my $P=$Self->_JSONPayload();return $P if ref $P ne 'HASH';
        return $Self->_Result(Result=>$SCIM->GroupCreate(%Base,$Self->_GroupFields($P)),SuccessCode=>201,ResourcePath=>'Groups');
    }
    if ( $Route eq 'group' && $Method eq 'GET' ) {
        return $Self->_Result(Result=>$SCIM->GroupGet(%Base,SCIMID=>$Request->GetParam(Param=>'id')//q{}),ResourcePath=>'Groups');
    }
    if ( $Route eq 'group' && $Method eq 'PUT' ) {
        my $P=$Self->_JSONPayload();return $P if ref $P ne 'HASH';my $Version=$Self->_IfMatch();return $Version if ref $Version;
        return $Self->_Result(Result=>$SCIM->GroupReplace(%Base,SCIMID=>$Request->GetParam(Param=>'id')//q{},ExpectedVersion=>$Version,$Self->_GroupFields($P)),ResourcePath=>'Groups');
    }
    if ( $Route eq 'group' && $Method eq 'PATCH' ) {
        return $Self->_GroupPatch(SCIM=>$SCIM,Base=>\%Base,ID=>$Request->GetParam(Param=>'id')//q{});
    }
    if ( $Route eq 'group' && $Method eq 'DELETE' ) {
        my $Version=$Self->_IfMatch();return $Version if ref $Version;my $R=$SCIM->GroupDelete(%Base,SCIMID=>$Request->GetParam(Param=>'id')//q{},ExpectedVersion=>$Version);
        return $Self->_Result(Result=>$R,SuccessCode=>204,NoContent=>1);
    }
    return $Self->_ErrorResponse( Code => $Route eq 'not_found' ? 404 : 405, Error => $Route eq 'not_found' ? 'NOT_FOUND' : 'METHOD_NOT_ALLOWED' );
}

sub _UserPatch {
    my ( $Self, %Param )=@_;my $P=$Self->_JSONPayload();return $P if ref $P ne 'HASH';
    return $Self->_ErrorResponse(Code=>400,Error=>'PATCH_INVALID') if ref $P->{Operations} ne 'ARRAY' || @{$P->{Operations}}>50;
    my $Version=$Self->_IfMatch();return $Version if ref $Version;my $Current=$Param{SCIM}->UserGet(%{$Param{Base}},SCIMID=>$Param{ID});return $Self->_Result(Result=>$Current)if!$Current->{Success};
    my $D=$Current->{Data};my %U=(UserName=>$D->{userName},ExternalID=>$D->{externalId},GivenName=>$D->{name}->{givenName},FamilyName=>$D->{name}->{familyName},Email=>$D->{emails}->[0]->{value},Active=>$D->{active},Surface=>$D->{'urn:careoncloud:params:scim:schemas:extension:esm:2.0:User'}->{surface});
    for my $O(@{$P->{Operations}}){return $Self->_ErrorResponse(Code=>400,Error=>'PATCH_INVALID')if ref$O ne'HASH'||($O->{op}//q{})!~m{\A(?:replace|Replace)\z}smx;my $Path=$O->{path}//q{};$Path='emails.value'if$Path=~m{\Aemails\[type[ ]+eq[ ]+"work"\]\.value\z}ismx;my %Map=(active=>'Active','name.givenName'=>'GivenName','name.familyName'=>'FamilyName','emails.value'=>'Email');return $Self->_ErrorResponse(Code=>400,Error=>'PATCH_PATH_UNSUPPORTED')if!$Map{$Path};$U{$Map{$Path}}=$O->{value}}
    return $Self->_Result(Result=>$Param{SCIM}->UserReplace(%{$Param{Base}},SCIMID=>$Param{ID},ExpectedVersion=>$Version,%U),ResourcePath=>'Users');
}

sub _GroupPatch {
    my($Self,%Param)=@_;my$P=$Self->_JSONPayload();return$P if ref$P ne'HASH';return$Self->_ErrorResponse(Code=>400,Error=>'PATCH_INVALID')if ref$P->{Operations}ne'ARRAY'||@{$P->{Operations}}>50;
    my$Version=$Self->_IfMatch();return$Version if ref$Version;my$Current=$Param{SCIM}->GroupGet(%{$Param{Base}},SCIMID=>$Param{ID});return$Self->_Result(Result=>$Current)if!$Current->{Success};my$D=$Current->{Data};my%Members=map{$_->{value}=>1}@{$D->{members}//[]};my$Display=$D->{displayName};
    for my$O(@{$P->{Operations}}){return$Self->_ErrorResponse(Code=>400,Error=>'PATCH_INVALID')if ref$O ne'HASH';my$Op=lc($O->{op}//q{});my$Path=$O->{path}//q{};
        if($Path eq'displayName'&&$Op eq'replace'){$Display=$O->{value};next}
        if($Path eq'members'&&($Op eq'add'||$Op eq'replace')){my@V=ref$O->{value}eq'ARRAY'?@{$O->{value}}:();%Members=()if$Op eq'replace';for my$M(@V){return$Self->_ErrorResponse(Code=>400,Error=>'PATCH_INVALID')if ref$M ne'HASH';$Members{$M->{value}}=1}next}
        if($Op eq'remove'&&$Path=~m{\Amembers\[value[ ]+eq[ ]+"([a-f0-9]{32})"\]\z}smx){delete$Members{$1};next}
        return$Self->_ErrorResponse(Code=>400,Error=>'PATCH_PATH_UNSUPPORTED');
    }
    my$Ext=$D->{'urn:careoncloud:params:scim:schemas:extension:esm:2.0:Group'};return$Self->_Result(Result=>$Param{SCIM}->GroupReplace(%{$Param{Base}},SCIMID=>$Param{ID},ExpectedVersion=>$Version,DisplayName=>$Display,ExternalID=>$D->{externalId},Role=>$Ext->{role},Members=>[sort keys%Members]),ResourcePath=>'Groups');
}

sub _UserFields {
    my($Self,$P)=@_;my $E=$P->{'urn:careoncloud:params:scim:schemas:extension:esm:2.0:User'}//{};my $Email=ref$P->{emails}eq'ARRAY'&&ref$P->{emails}->[0]eq'HASH'?$P->{emails}->[0]->{value}:undef;
    return (UserName=>$P->{userName},ExternalID=>$P->{externalId},GivenName=>ref$P->{name}eq'HASH'?$P->{name}->{givenName}:undef,FamilyName=>ref$P->{name}eq'HASH'?$P->{name}->{familyName}:undef,Email=>$Email,Active=>exists$P->{active}?$P->{active}:1,Surface=>$E->{surface}//$Kernel::OM->Get('Kernel::Config')->Get('D724::SCIM::DefaultSurface')//'agent');
}
sub _GroupFields { my($Self,$P)=@_;my $E=$P->{'urn:careoncloud:params:scim:schemas:extension:esm:2.0:Group'}//{};my @M=ref$P->{members}eq'ARRAY'?map{ref$_ eq'HASH'?$_->{value}:q{}}@{$P->{members}}:();return(DisplayName=>$P->{displayName},ExternalID=>$P->{externalId},Role=>$E->{role},Members=>\@M) }

sub _Filter {
    my($Self)=@_;my $F=$Kernel::OM->Get('Kernel::System::Web::Request')->GetParam(Param=>'filter');return()if!defined$F||!length$F;
    return(Response=>$Self->_ErrorResponse(Code=>400,Error=>'FILTER_UNSUPPORTED',ScimType=>'invalidFilter'))if$F!~m{\A(id|userName|displayName|externalId)[ ]+eq[ ]+"([^"\x00-\x1f]{1,255})"\z}smx;
    return(FilterAttribute=>$1,FilterOperator=>'eq',FilterValue=>$2);
}
sub _IfMatch { my($Self)=@_;my $H=$Kernel::OM->Get('Kernel::System::Web::Request')->Header('If-Match')//q{};return $1 if$H=~m{\AW/"([1-9][0-9]*)"\z}smx;return $Self->_ErrorResponse(Code=>428,Error=>'IF_MATCH_REQUIRED') }
sub _Bearer { my($Self)=@_;my $H=$Kernel::OM->Get('Kernel::System::Web::Request')->Header('Authorization')//q{};return $1 if$H=~m{\ABearer[ ]+([a-zA-Z0-9]{64})\z}smx;return }
sub _JSONPayload { my($Self)=@_;my $R=$Kernel::OM->Get('Kernel::System::Web::Request');my $CT=$R->Header('Content-Type')//q{};return $Self->_ErrorResponse(Code=>415,Error=>'CONTENT_TYPE_UNSUPPORTED')if$CT!~m{\Aapplication/(?:scim\+)?json(?:[ ]*;|\z)}ismx;my $C=$R->Content()//q{};return $Self->_ErrorResponse(Code=>413,Error=>'BODY_TOO_LARGE')if length$C>131072;my $P=eval{$Kernel::OM->Get('Kernel::System::JSON')->Decode(Data=>$C)};return $Self->_ErrorResponse(Code=>400,Error=>'JSON_INVALID')if$@||ref$P ne'HASH';return$P }

sub _Result {
    my($Self,%P)=@_;my $R=$P{Result};if(!$R->{Success}){my%C=(TOKEN_INVALID=>401,FORBIDDEN=>403,CROSS_TENANT=>403,RATE_LIMITED=>429,NOT_FOUND=>404,VERSION_CONFLICT=>412,VERSION_REQUIRED=>428,IMMUTABLE_ATTRIBUTE=>400,FILTER_UNSUPPORTED=>400,FILTER_VALUE_INVALID=>400,PAGINATION_INVALID=>400,USER_NAME_CONFLICT=>409,EXTERNAL_ID_CONFLICT=>409,NATIVE_LOGIN_CONFLICT=>409,GROUP_CONFLICT=>409,CUSTOMER_COMPANY_NOT_FOUND=>409);return$Self->_ErrorResponse(Code=>$C{$R->{Error}}//400,Error=>$R->{Error},ScimType=>$R->{Error}eq'FILTER_UNSUPPORTED'?'invalidFilter':undef)}
    my $Response=$Kernel::OM->Get('Kernel::System::Web::Response');my $Code=$P{SuccessCode}//200;$Response->Code($Code);$Response->Header('Cache-Control'=>'no-store');$Response->Header('X-Content-Type-Options'=>'nosniff');return q{} if$P{NoContent};my $D=$R->{Data};$Response->Header('Content-Type'=>'application/scim+json;charset=UTF-8');if(ref$D eq'HASH'&&ref$D->{meta}eq'HASH'){$Response->Header('ETag'=>$D->{meta}->{version});$Response->Header('Location'=>'/careoncloud/scim/v2/'.($P{ResourcePath}//q{}).'/'.$D->{id})if$P{ResourcePath}}return$Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>$D,SortKeys=>1)
}
sub _ErrorResponse { my($Self,%P)=@_;my$R=$Kernel::OM->Get('Kernel::System::Web::Response');$R->Code($P{Code});$R->Header('Content-Type'=>'application/scim+json;charset=UTF-8');$R->Header('Cache-Control'=>'no-store');my%D=(schemas=>['urn:ietf:params:scim:api:messages:2.0:Error'],status=>''.$P{Code},detail=>$P{Error});$D{scimType}=$P{ScimType}if$P{ScimType};return$Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>\%D,SortKeys=>1) }
sub _Discovery { my($Self,$R)=@_;my%D=(service_provider_config=>{schemas=>['urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig'],patch=>{supported=>1},bulk=>{supported=>0,maxOperations=>0,maxPayloadSize=>0},filter=>{supported=>1,maxResults=>200},changePassword=>{supported=>0},sort=>{supported=>0},etag=>{supported=>1},authenticationSchemes=>[{type=>'oauthbearertoken',name=>'OAuth Bearer Token',description=>'Tenant-bound CareOnCloud API token'}]},schemas=>{schemas=>['urn:ietf:params:scim:api:messages:2.0:ListResponse'],totalResults=>0,startIndex=>1,itemsPerPage=>0,Resources=>[]},resource_types=>{schemas=>['urn:ietf:params:scim:api:messages:2.0:ListResponse'],totalResults=>2,startIndex=>1,itemsPerPage=>2,Resources=>[{id=>'User',name=>'User',endpoint=>'/Users',schema=>'urn:ietf:params:scim:schemas:core:2.0:User'},{id=>'Group',name=>'Group',endpoint=>'/Groups',schema=>'urn:ietf:params:scim:schemas:core:2.0:Group'}]});my$Response=$Kernel::OM->Get('Kernel::System::Web::Response');$Response->Code(200);$Response->Header('Content-Type'=>'application/scim+json;charset=UTF-8');return$Kernel::OM->Get('Kernel::System::JSON')->Encode(Data=>$D{$R},SortKeys=>1) }

1;
