# SEC-01b Ticket Read/Search Tenant Policy

Durum: ticket read/search alt kapisi tamamlandi (`2026-07-24`). Genel `SEC-01b` daemon, rapor, cache ve diger domain adapter'lari tamamlanana kadar aciktir.

## Garanti

`D724TicketAudit 0.6.1`, OTOBO'nun resmi `Ticket::CustomModule` uzatma noktasinda merkezi `D724::TicketPolicy` servisini yukler.

- Agent baglami aktif `d724_tenant_agent_role` kayitlarindan, customer baglami aktif customer-company tenant'inden uretilir.
- `TicketSearch` sorgusu calismadan once izinli tenant listesi `CustomerID` predikati olarak eklenir. Cagiranin filtresi izinli tenant'larla kesistirilir; bos kesisim sonuc dondurmez.
- `CustomerIDRaw` tenant filtresini atlayabildigi icin policy etkinken reddedilir.
- Baglamsiz, uyeliksiz, gecersiz veya inactive tenant kimlikleri fail-closed davranir.
- Tekil erisim immutable `d724_ticket_scope` ve aktif tenant kaydindan dogrulanir; ticket'in degisebilir UI alanlarina guvenilmez.
- Generic Interface `TicketGet`, `TicketHistoryGet` ve `TicketUpdate` ortak erisim kontrolu hem OTOBO queue/customer iznini hem D724 tenant iznini zorunlu tutar.
- Platform bypass yalniz mevcut `D724::TenantGuard::AllowPlatformAdmin` emergency ayari ve acik `platform_admin` baglami ile mumkundur.

Filtre sonuctan sonra uygulanmaz. Bu sayede `Limit`, siralama ve `COUNT` altinda baska tenant kayitlarinin pencereyi doldurup izinli kayitlari gizlemesi engellenir.

## Kanit

- `TicketPolicy.t`: ayni-tenant arama/tekil erisim/GI izinleri; cross-tenant arama, tekil erisim ve GI redleri; raw bypass, uyeliksiz agent ve unbound ticket redleri.
- Tum D724 regresyonu: 26 dosya / 486 test `PASS`.
- Kalici demo kabul betigi: `development/d724/Accept-TicketPolicy.pl` agent directory baglamindan `D724AUD20260724001` kaydini arar, scope tenant'ini dogrular, raw bypass'i reddeder ve Generic Interface ortak kontrolunu calistirir.
- Test sunucusu kabul sonucu: `demo.agent` / UserID `47`, tenant `d724-demo`, gorunen ticket listesi `[9]`, raw bypass denied ve Generic Interface access `1`.
- OPM SHA-256: `a574c4e22fef7520c7d86a7ab418f13243ae8e8963e742150b1c6d097e3d9e29`.

## Acik kapsam

Generic Interface icin OAuth client kimligi, operasyon-bazli role/action matrisi, rate limit, idempotency ve surumlu `/api/v1` kontrati `API-01` kapsamindadir. Elasticsearch adapter'i, rapor/statistik sorgulari, cache key tenant namespace'i, daemon actor baglami ve ticket detay UI direct-link savunmasinin genis kabul matrisi genel `SEC-01b` icinde aciktir.
