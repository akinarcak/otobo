# AUD-01b Catalog Atomic Audit

Durum: tamamlandi (`2026-07-24`).

## Kapsam

`D724Catalog 0.5.2`, asagidaki tenant-kapsamli mutation'lari normalize audit zincirine baglar:

- `catalog.service.created` / `catalog.service.updated`
- `catalog.offering.created` / `catalog.offering.updated`
- `catalog.item.created` / `catalog.item.updated`
- `catalog.item_schema.created` / `catalog.item_schema.updated`

Object tipleri sirasiyla `catalog_service`, `catalog_offering`, `catalog_item` ve `catalog_item_schema` olarak sabittir. Correlation ID key veya catalog item ID uzerinden kararlidir. Her olay create kimligi ya da yeni optimistic version iceren tenant-local bir dedupe key tasir.

## Transaction garantisi

Service, offering, item ve schema yazim girisleri production `AutoCommit` baglantisinda transaction acar. Repository mutasyonu, optimistic version kontrolu ve audit head/event append ayni transaction'a katilir. Audit disabled, DB hatasi veya hash append hatasinda domain mutasyonu commit edilmez. Bir ust transaction varsa katalog islemi ona katilir ve commit sahipligini devralmaz.

## Guvenlik

- `catalog.manage` karari mutation'dan once zorunludur.
- Tenant predicate'i tum entity ve parent sorgularinda korunur.
- Cross-tenant parent ID `PARENT_NOT_FOUND`, cross-tenant yetki `FORBIDDEN` ile fail-closed davranir.
- Audit actor kimligi yetkili subject'ten, tenant kimligi policy-korumali mutation context'inden gelir.
- Stale version veya gecersiz schema audit olayi uretmez.

## Kanit

- Catalog paketi: 6 dosya / 73 test `PASS`.
- Tum urun regresyonu: 23 dosya / 402 test `PASS`.
- Unit transaction kontrati: failure sonrasi mutation `0`, success sonrasi durable row `1`.
- Gercek demo hata enjeksiyonu:
  - service create audit failure sonrasi row `0`;
  - service update audit failure sonrasi ad `Atomic Audit Service`, version `1` olarak kaldi;
  - schema audit failure sonrasi schema row `0`;
  - ayni girdilerin retry'lari basarili oldu.
- Gercek kabul nesneleri: service `123`, offering `83`, item `104`.
- Bes sirali normalize olay farkli dedupe key'lerle kaydedildi.
- Demo tenant zinciri kabul sonunda `Valid=1`, 20 event.

## Acik core kapsam

Bu milestone sonrasinda CareOnCloud ESM ticket/MIME article cekirdek atomikligi `AUD-01b-ticket-core`, tenant-directory atomikligi `AUD-01b-directory` kapsaminda tamamlanmistir. Generic Interface, kalan ticket/Chat ve commitment scheduler/escalation adapter'lari aciktir.
