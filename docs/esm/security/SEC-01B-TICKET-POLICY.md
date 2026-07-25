# SEC-01b Ticket Read/Search Tenant Policy

Durum: ticket read/search alt kapisi tamamlandi (`2026-07-24`). Genel `SEC-01b` cache, search ve diger domain adapter'lari tamamlanana kadar aciktir.

## Garanti

`D724TicketAudit 0.7.1`, OTOBO'nun resmi `Ticket::CustomModule` uzatma noktasinda merkezi `D724::TicketPolicy` servisini yukler.

- Agent baglami aktif `d724_tenant_agent_role` kayitlarindan, customer baglami aktif customer-company tenant'inden uretilir.
- `TicketSearch` sorgusu calismadan once izinli tenant listesi `CustomerID` predikati olarak eklenir. Cagiranin filtresi izinli tenant'larla kesistirilir; bos kesisim sonuc dondurmez.
- `CustomerIDRaw` tenant filtresini atlayabildigi icin policy etkinken reddedilir.
- Baglamsiz, uyeliksiz, gecersiz veya inactive tenant kimlikleri fail-closed davranir.
- Tekil erisim immutable `d724_ticket_scope` ve aktif tenant kaydindan dogrulanir; ticket'in degisebilir UI alanlarina guvenilmez.
- Generic Interface `TicketGet`, `TicketHistoryGet` ve `TicketUpdate` ortak erişim kontrolü hem OTOBO queue/customer iznini hem tenant iznini zorunlu tutar. Ayrıca ayrı `integration.ticket.get`, `integration.ticket.history` ve `integration.ticket.update` kararları uygulanır; requester/auditor update yapamaz ve tanımlanamayan operasyon fail-closed reddedilir.
- Platform bypass yalniz mevcut `D724::TenantGuard::AllowPlatformAdmin` emergency ayari ve acik `platform_admin` baglami ile mumkundur.

Filtre sonuctan sonra uygulanmaz. Bu sayede `Limit`, siralama ve `COUNT` altinda baska tenant kayitlarinin pencereyi doldurup izinli kayitlari gizlemesi engellenir.

## Kanit

- `TicketPolicy.t`: ayni-tenant arama/tekil erisim/GI izinleri; cross-tenant arama, tekil erisim ve GI redleri; raw bypass, uyeliksiz agent ve unbound ticket redleri.
- Tum D724 regresyonu: 26 dosya / 486 test `PASS`.
- Kalici demo kabul betigi: `development/d724/Accept-TicketPolicy.pl` agent directory baglamindan `D724AUD20260724001` kaydini arar, scope tenant'ini dogrular, raw bypass'i reddeder ve Generic Interface ortak kontrolunu calistirir.
- Test sunucusu kabul sonucu: `demo.agent` / UserID `47`, tenant `d724-demo`, gorunen ticket listesi `[9]`, raw bypass denied ve Generic Interface access `1`.
- OPM SHA-256: `a574c4e22fef7520c7d86a7ab418f13243ae8e8963e742150b1c6d097e3d9e29`.

## Acik kapsam

Generic Interface için OAuth client kimliği, rate limit, idempotency ve sürümlü `/api/v1` kontratı `API-01` kapsamındadır. Daemon actor bağlamı `SEC-01B-DAEMON.md`, operasyon raporu `REPORT-01.md`, cache namespace'i `SEC-01B-CACHE.md` ve aktif Elasticsearch runtime'i `SEC-01B-SEARCH.md` ile tamamlanmıştır. Operasyon-bazlı role/action matrisi `D724TenantGuard 0.7.0` ve `D724TicketAudit 0.8.1` ile kapatılmıştır.
