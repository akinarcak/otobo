# SEC-01B Elasticsearch Search Boundary

Durum: uygulama request-boundary kapisi tamamlandi (`2026-07-25`). Aktif
Elasticsearch profiliyle index migration ve iki-tenant network acceptance aciktir.

## Tehdit ve kontrat

OTOBO'nun ticket Elasticsearch yolu `Kernel::System::Elasticsearch::TicketSearch`
ile baslar ve tum index sorgulari ortak
`Kernel::GenericInterface::Invoker::Elasticsearch::Search::PrepareRequest`
sinirindan gecer. `D724TicketAudit 0.7.1`, upstream cekirdek dosyayi kopyalamadan
mevcut `Ticket::CustomModule` extension katmaninda iki noktayi birlikte korur:

1. TicketSearch, agent kimligini kalici tenant directory'den veya customer kimligini
   server-side customer kaydindan cozer.
2. Her tenant icin merkezi `search.read` karari alinir; unrestricted/global context
   Elasticsearch icin kabul edilmez.
3. Kullanicinin `CustomerID` istegi trusted tenant scope ile kesistirilir ve
   `CustomerIDRaw` reddedilir.
4. Final invoker, serialize edilen query body'ye exact `terms.CustomerID` tenant
   filtresini yeniden ekler.
5. Trusted context olmadan dogrudan invoker cagrisi ve tenant-safe ilan edilmemis
   `customer`, `customeruser`, `configitem`, `faq` gibi global index aramalari
   fail-closed reddedilir.

Ticket `CustomerID` alani D724'ta aktif tenant anahtaridir. `D724TicketAudit`, ticket
olustururken ayni degeri immutable `d724_ticket_scope.tenant_id` olarak yazar ve
sonraki cross-tenant customer degisimini transaction icinde reddeder. Bu nedenle
Elasticsearch discriminator'i ile authoritative scope arasindaki esitlik urun
invariant'idir.

## Operasyon

`Admin::D724::TicketAuditStatus --json` artik search policy etkinligini, contract
surumunu, desteklenen index listesini, tenant field'ini ve direct-unscoped davranisini
raporlar. Yalniz `ticket` index'i tenant-safe allow-list'tedir; konfigurasyona baska
bir index eklemek kod seviyesindeki supported-index kapisini asamaz.

## Kanit ve sinir

`SearchPolicy.t`, benzersiz bir agent ve iki tenant ile trusted scope, merkezi action,
exact final filter, direct bypass reddi, unsafe index reddi ve disabled-policy
fail-closed davranisini test eder. `Accept-SearchPolicy.pl`, gercek demo agent UserID
`47` icin OTOBO invoker'inin serialize ettigi body'de yalniz `d724-demo` filtresini
dogrulamistir.

Hedefli guvenlik regresyonu 5 dosya / 204 test; tam D724 regresyonu 42 dosya / 859
test ile `PASS` sonucudur. Test sunucusunda `Elasticsearch::Active=false` oldugu icin
bu kanit request serialization sinirindadir; gercek index hit/miss ve migration kaniti
search profili guvenilir bicimde indirildiginde ayri runtime kapisinda tamamlanacaktir.
