# FLOW-01 Talep Orkestrasyonu

## Karar

Talep, onay ve fulfillment kayitlari OTOBO icinde GPL-3.0 `D724Request` paketi olarak tutulur. Katalog semasi calisma aninda kopyalanir; sonradan katalog degisse bile acilmis talebin onay ve gorev plani degismez.

## Durum modeli

- Talep: `initializing -> awaiting_approval -> in_fulfillment -> fulfilled`; alternatif sonuclar `rejected`, `fulfillment_failed` ve kurtarilabilir kurulum hatasi `submission_failed`.
- Onay: `pending -> approved|rejected`.
- Gorev: onay beklerken `blocked`; sonra `pending -> in_progress -> completed|failed`. Son gorevin tamamlanmasi talebi `fulfilled` yapar.

## Guvenlik ve tutarlilik

- Tenant kimligi musteri oturumundaki `CustomerID` veya agent directory context'inden gelir; form parametresinden guvenilmez.
- Agent okuma/yazma islemleri `D724TenantGuard` icindeki `case.read` ve `case.update` kararlarindan gecer.
- Onayi yalniz workflow'da belirtilen tenant-bazli `tenant_admin` veya `service_owner` rolu verebilir.
- Form cevaplari katalog semasina gore sunucu tarafinda tip, zorunluluk, uzunluk ve secenek allow-list kontrollerinden gecer.
- Musteri, requester ve tenant kapsamli idempotency anahtari kullanir. Ayni payload replay edilir; farkli payload `IDEMPOTENCY_CONFLICT` alir.
- Onay ve gorev yazmalari beklenen version ile optimistic locking uygular; terminal durumlar yeniden acilamaz.
- CareOnCloud ESM framework CSRF token'i tum portal ve agent POST formlarinda zorunludur.

## Dogrulama

Test sunucusunda bes D724 paketinin 14 test dosyasinda 227 test birlikte gecmistir. Oturumlu HTTP kabul testi katalog item formunun tek ve gecerli CSRF token'i urettigini, submit'in `REQ-*` makbuzu dondurdugunu ve kaydin tenant-kapsamli agent workbench'te gorundugunu dogrular.
