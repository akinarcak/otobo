# --
# Copyright (C) 2026 Data Market Bilgi Hizmetleri A.S.
# SPDX-License-Identifier: GPL-3.0-only
# --
use v5.24; use strict; use warnings;
use Test2::V0; use Kernel::System::UnitTest::RegisterOM;
$Kernel::OM->ObjectParamAdd('Kernel::System::UnitTest::Helper'=>{RestoreDatabase=>0});
my $Helper=$Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $DB=$Kernel::OM->Get('Kernel::System::DB'); my $Identity=$Kernel::OM->Get('Kernel::System::CareOnCloud::Identity');
my $Key='identity-tx-'.lc $Helper->GetRandomID(); my $Zero='0'x64; my $Version=1; my $Handle=$DB->Connect();
$Handle->commit() if !$Handle->{AutoCommit};
ok($Handle->{AutoCommit},'identity transaction test starts in production-style AutoCommit mode');
my $Failed=$Identity->_TransactionRun(Code=>sub{my @V=($Key,$Zero,$Version);my @B=map{\$_}@V;$DB->Do(SQL=>'INSERT INTO careoncloud_audit_head (tenant_id,last_sequence,last_hash,version,change_time) VALUES (?,0,?,?,current_timestamp)',Bind=>\@B);return{Success=>0,Error=>'INJECTED_FAILURE'}});
is($Failed->{Error},'INJECTED_FAILURE','domain failure is returned');
$DB->Prepare(SQL=>'SELECT COUNT(*) FROM careoncloud_audit_head WHERE tenant_id=?',Bind=>[\$Key]); my($Count)=$DB->FetchrowArray();
is($Count,0,'failed identity transaction leaves no mutation');
my $Committed=$Identity->_TransactionRun(Code=>sub{my @V=($Key,$Zero,$Version);my @B=map{\$_}@V;$DB->Do(SQL=>'INSERT INTO careoncloud_audit_head (tenant_id,last_sequence,last_hash,version,change_time) VALUES (?,0,?,?,current_timestamp)',Bind=>\@B);return{Success=>1}});
ok($Committed->{Success},'successful identity transaction commits');
$DB->Prepare(SQL=>'SELECT COUNT(*) FROM careoncloud_audit_head WHERE tenant_id=?',Bind=>[\$Key]);($Count)=$DB->FetchrowArray();is($Count,1,'successful mutation is durable');
$DB->Do(SQL=>'DELETE FROM careoncloud_audit_head WHERE tenant_id=?',Bind=>[\$Key]);
done_testing;
