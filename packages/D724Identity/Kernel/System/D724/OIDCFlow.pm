# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
package Kernel::System::D724::OIDCFlow;
use v5.24; use strict; use warnings;
use Crypt::PRNG qw(random_bytes);
use Digest::SHA qw(sha256 sha256_hex);
use MIME::Base64 qw(encode_base64url);
use URI ();

our $VERSION='0.2.0';
our @ObjectDependencies=qw(Kernel::System::DB Kernel::System::D724::Identity Kernel::System::OpenIDConnect::Token);
sub new{return bless{},$_[0]}

sub Begin {
    my($Self,%Param)=@_;
    my $Provider=$Kernel::OM->Get('Kernel::System::D724::Identity')->ProviderRouteGetByKey(%Param);
    return $Self->_Error('PROVIDER_NOT_FOUND') if !$Provider;
    return $Self->_Error('BROWSER_BINDING_INVALID') if ($Param{BrowserBinding}//q{})!~m{\A[^\x00-\x1f]{32,512}\z}smx;
    return $Self->_Error('RETURN_PATH_INVALID') if ($Param{ReturnPath}//q{})!~m{\A/otobo/(?!/)[A-Za-z0-9?&=._~/%+-]{0,1000}\z}smx;
    my $State=encode_base64url(random_bytes(32)); my $Nonce=encode_base64url(random_bytes(32)); my $Verifier=encode_base64url(random_bytes(64));
    my $Challenge=encode_base64url(sha256($Verifier));
    my($StateDigest,$BrowserDigest,$NonceDigest,$VerifierDigest)=map{sha256_hex($_)}($State,$Param{BrowserBinding},$Nonce,$Verifier);
    my @V=($StateDigest,$Provider->{TenantID},$Provider->{ID},$BrowserDigest,$NonceDigest,$VerifierDigest,$Param{ReturnPath});my @B=map{\$_}@V;
    return $Self->_Error('FLOW_CREATE_FAILED') if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL=>q{INSERT INTO d724_oidc_flow (state_digest,tenant_id,provider_id,browser_digest,nonce_digest,verifier_digest,return_path,status,expires_at,create_time,change_time) VALUES (?,?,?,?,?,?,?,'pending',DATE_ADD(current_timestamp,INTERVAL 300 SECOND),current_timestamp,current_timestamp)},Bind=>\@B);
    return{Success=>1,Data=>{State=>$State,Nonce=>$Nonce,CodeVerifier=>$Verifier,CodeChallenge=>$Challenge,CodeChallengeMethod=>'S256',TenantID=>$Provider->{TenantID},ProviderKey=>$Provider->{Key},ReturnPath=>$Param{ReturnPath},ExpiresIn=>300}};
}

sub MetadataValidate {
    my($Self,%Param)=@_; my $Provider=$Param{Provider}; my $M=$Param{Metadata};
    return $Self->_Error('PROVIDER_INVALID') if ref $Provider ne'HASH'; return $Self->_Error('METADATA_INVALID') if ref $M ne'HASH';
    return $Self->_Error('ISSUER_MISMATCH') if ($M->{issuer}//q{}) ne ($Provider->{Issuer}//q{});
    my $Origin=$Self->_Origin($Provider->{Issuer}); return $Self->_Error('ISSUER_INVALID') if !$Origin;
    for my $Key(qw(authorization_endpoint token_endpoint jwks_uri)){
        my $EndpointOrigin=$Self->_Origin($M->{$Key}); return $Self->_Error(uc($Key).'_INVALID') if !$EndpointOrigin || $EndpointOrigin ne $Origin;
    }
    my %Supported=map{$_=>1}@{$M->{id_token_signing_alg_values_supported}//[]};
    return $Self->_Error('SIGNING_ALGORITHM_UNSUPPORTED') if !$Supported{RS256} && !$Supported{ES256};
    return{Success=>1,Data=>{Issuer=>$Provider->{Issuer},AuthorizationEndpoint=>$M->{authorization_endpoint},TokenEndpoint=>$M->{token_endpoint},JWKSURI=>$M->{jwks_uri},AllowedAlgorithms=>[grep{$Supported{$_}}qw(ES256 RS256)]}};
}

sub CallbackVerify {
    my ( $Self, %Param ) = @_;
    my $DB = $Kernel::OM->Get('Kernel::System::DB');
    my $Handle = $DB->Connect();
    return $Self->_Error('DATABASE_UNAVAILABLE') if !$Handle;

    for my $Key (qw(State CodeVerifier)) {
        return $Self->_Error('CALLBACK_PARAMETER_INVALID')
            if ( $Param{$Key} // q{} ) !~ m{\A[A-Za-z0-9_-]{20,128}\z}smx;
    }
    return $Self->_Error('CALLBACK_PARAMETER_INVALID')
        if ( $Param{BrowserBinding} // q{} ) !~ m{\A[^\x00-\x1f]{32,512}\z}smx;
    return $Self->_Error('TOKEN_INVALID')
        if !defined $Param{IDToken} || !length $Param{IDToken} || length $Param{IDToken} > 20_000;

    my $OwnTransaction = $Handle->{AutoCommit} ? 1 : 0;
    my $Result;
    my $OK = eval {
        $DB->BeginWork() if $OwnTransaction;
        my $StateDigest = sha256_hex( $Param{State} );
        # state_digest is the primary key, so the query already returns at most one
        # row. Avoid DB.pm's appended LIMIT here because MariaDB requires FOR UPDATE
        # to remain the final clause.
        $DB->Prepare(SQL=>q{SELECT f.tenant_id,f.provider_id,f.browser_digest,f.nonce_digest,f.verifier_digest,f.return_path,f.status,p.key_name,p.issuer,p.audience FROM d724_oidc_flow f INNER JOIN d724_identity_provider p ON p.id=f.provider_id WHERE f.state_digest=? AND f.expires_at>current_timestamp FOR UPDATE},Bind=>[\$StateDigest]);
        my @R=$DB->FetchrowArray(); if(!@R){$Result=$Self->_Error('FLOW_NOT_FOUND_OR_EXPIRED')}
        elsif($R[6] ne'pending'){$Result=$Self->_Error('FLOW_REPLAY')}
        elsif(!$Self->_Equal($R[2],sha256_hex($Param{BrowserBinding}))){$Result=$Self->_Error('BROWSER_BINDING_MISMATCH')}
        elsif(!$Self->_Equal($R[4],sha256_hex($Param{CodeVerifier}))){$Result=$Self->_Error('PKCE_VERIFIER_MISMATCH')}
        else{
            my $Token=$Kernel::OM->Get('Kernel::System::OpenIDConnect::Token')->Validate(Token=>$Param{IDToken},OpenIDConfig=>$Param{OpenIDConfig},ExpectedAudience=>$R[9],AuthorizedParty=>$R[9],Leeway=>2);
            if(!$Token->{Success}){$Result=$Self->_Error('TOKEN_SIGNATURE_OR_CLAIMS_INVALID')}
            else{my $C=$Token->{TokenData};my @Aud=ref$C->{aud}eq'ARRAY'?@{$C->{aud}}:($C->{aud});my $AudienceExact=grep{defined$_&&$_ eq$R[9]}@Aud;
                if(($C->{iss}//q{})ne$R[8]){$Result=$Self->_Error('TOKEN_ISSUER_MISMATCH')}
                elsif(!$AudienceExact){$Result=$Self->_Error('TOKEN_AUDIENCE_MISMATCH')}
                elsif(!$Self->_Equal($R[3],sha256_hex($C->{nonce}//q{}))){$Result=$Self->_Error('TOKEN_NONCE_MISMATCH')}
                else{$Result=$Kernel::OM->Get('Kernel::System::D724::Identity')->VerifiedClaimsResolve(Verification=>{Verified=>1,Verifier=>'oidc',Issuer=>$R[8],Audience=>$R[9],Claims=>$C});
                    if($Result->{Success}){
                        my $Consumed = $DB->Do(
                            SQL => q{UPDATE d724_oidc_flow SET status='consumed',change_time=current_timestamp WHERE state_digest=? AND status='pending'},
                            Bind => [\$StateDigest],
                        );
                        die "OIDC flow consume failed\n" if !$Consumed;
                        $Result->{Data}->{ReturnPath}=$R[5];
                    }
                }
            }
        }
        if ($OwnTransaction) {
            $Result->{Success} ? $Handle->commit() : $DB->Rollback();
        }
        1;
    };
    if (!$OK) {
        eval { $DB->Rollback() } if $OwnTransaction;
        return $Self->_Error('CALLBACK_TRANSACTION_FAILED');
    }
    return $Result;
}

sub _Origin {my($Self,$URL)=@_;return if !defined$URL||length($URL)>1000;my$U=URI->new($URL);return if lc($U->scheme//q{})ne'https'||!$U->host||defined$U->userinfo||defined$U->fragment||defined$U->query;return lc($U->scheme).'://'.lc($U->host).(defined$U->port&&$U->port!=443?':'.$U->port:q{})}
sub _Equal {my($Self,$A,$B)=@_;return 0 if !defined$A||!defined$B||length($A)!=length($B);my$D=0;for my$I(0..length($A)-1){$D|=ord(substr($A,$I,1))^ord(substr($B,$I,1))}return$D==0?1:0}
sub _Error{return{Success=>0,Error=>$_[1]}}
1;
