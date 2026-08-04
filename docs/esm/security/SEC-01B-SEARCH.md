# SEC-01B Elasticsearch Search Boundary

Durum: request-boundary ve aktif runtime kapilari tamamlandi (`2026-07-25`).

## Tehdit ve kontrat

CareOnCloud ESM'nun ticket Elasticsearch yolu `Kernel::System::Elasticsearch::TicketSearch`
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

## Runtime kurulumu ve kanit

Search servisi `rotheross/otobo-elasticsearch:latest-11_1` image'inin
`sha256:96966a51f3c9a5811473a1b9ec6d262e0857e92d4c6475be9b432af5945c753f`
digest'ine sabitlenmistir. Elasticsearch 8.19.3 yalniz Compose ic aginda 9200/9300
portlarini acar; host portu yayinlamaz. Cluster `green` ve CareOnCloud ESM resmi
`Maint::Elasticsearch::TestConnection` kontrolu basarilidir.

`elasticsearch-webservice.yml`, requester host'unu `http://elastic:9200` olarak
surumler. `Configure-Elasticsearch.pl`, var olan invalid kaydi idempotent bicimde
gunceller veya eksikse olusturur; beklenmeyen host'u reddeder.

`Maint::Elasticsearch::Migration --target t` iki authoritative MariaDB ticket'ini
ticket index'ine tasimistir. Regresyon sonrasi ayni migration tekrar calistirilarak
unit testlerin dis-index yan etkileri temizlenmis, refresh sonrasi document count `2`
olmustur.

`SearchPolicy.t`, benzersiz bir agent ve iki tenant ile trusted scope, merkezi action,
exact final filter, direct bypass reddi, unsafe index reddi ve disabled-policy
fail-closed davranisini test eder. `Accept-SearchPolicy.pl`, gercek demo agent UserID
`47` icin CareOnCloud ESM invoker'inin serialize ettigi body'de yalniz `d724-demo` filtresini
dogrulamistir. `Accept-ElasticsearchRuntime.pl`, aktif index'e ayni full-text degeri
tasiyan iki gecici tenant dokumani yazmis; CareOnCloud ESM TicketSearch uzerinden yalniz own
tenant hit'ini almis, explicit cross-tenant istegi reddetmis ve iki fixture'i silmistir.

Hedefli guvenlik regresyonu 5 dosya / 204 test; Elasticsearch aktifken tam D724
regresyonu 42 dosya / 859 test ile `PASS` sonucudur. Runtime kabul sonucu
`cross_tenant_hit_excluded=true` ve `explicit_cross_tenant_denied=true` dondurmustur.
