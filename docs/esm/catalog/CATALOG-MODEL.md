# CAT-01 Hizmet Portfoyu ve Katalog Modeli

## Varliklar

- `Service`: Kurumun sundugu uctan uca hizmet. Ornek: Calisan Dijital Calisma Ortami.
- `ServiceOffering`: Hizmetin belirli hedef kitle, kanal veya fulfillment yontemiyle sunumu. Ornek: Standart Dizustu Bilgisayar.
- `CatalogItem`: Portalda talep edilebilen urun. Ornek: Yeni Dizustu Bilgisayar Talebi.

Iliski `Service 1..n ServiceOffering 1..n CatalogItem` seklindedir. Uc varlik da bagimsiz tenant sinirina, tenant icinde benzersiz ve degismez bir key'e, lifecycle status'e ve optimistic version alanina sahiptir.

## Lifecycle

Gecerli durumlar `draft`, `active`, `suspended`, `retired` olarak sinirlidir. Ilk kayit varsayilan olarak `draft` olur. Fiziksel silme ilk surum API'sinde yoktur; kullanilmayan kayitlar `retired` yapilir. Bu karar audit, talep gecmisi ve rapor referanslarini korur.

## Guvenlik ve veri butunlugu

1. Her repository cagrisi trusted `Subject`, sayisal OTOBO `UserID` ve `TenantID` ister.
2. Read/list `catalog.read`, create/update `catalog.manage` karari gerektirir.
3. SQL sorgulari `id` ile birlikte daima `tenant_id` kosulu kullanir.
4. List sorgusu once `D724TenantGuard::ScopeGet`, sonra action karari alir.
5. Tenant disindaki bir ID, subject'in kendi tenant'i ile sorulursa `NOT_FOUND`; hedef tenant acik verilirse policy tarafindan `FORBIDDEN` doner.
6. Parent iliskileri repository'de `(tenant_id, parent_id)` birlikte dogrulanir. OTOBO paket sema ceviricisi cok sutunlu foreign key tanimini ayri kisitlara donusturdugu icin veritabani tek basina bu cifti garanti etmez; ham SQL yazma yetkisi uygulama kullanicisindan alinmali ve bu sinir release oncesi migration ile sertlestirilmelidir.
7. Key tenant icinde benzersizdir ve create sonrasi degistirilemez.
8. Update zorunlu `ExpectedVersion` kullanir. Stale yazma `VERSION_CONFLICT` doner ve veri ezilmez.
9. Liste boyutu yapilandirmayla sinirlanir; tenantsiz/global liste API'si yoktur.
10. Repository cache kullanmaz. Cache eklendiginde tenant ID anahtarin zorunlu parcasi olacaktir.

## Ilk API

`Kernel::System::D724::Catalog` su metodlari sunar:

- `ServiceCreate`, `ServiceGet`, `ServiceList`, `ServiceUpdate`
- `OfferingCreate`, `OfferingGet`, `OfferingList`, `OfferingUpdate`
- `CatalogItemCreate`, `CatalogItemGet`, `CatalogItemList`, `CatalogItemUpdate`

Tum metodlar `{ Success => 1, Data => ... }` veya `{ Success => 0, Error => CODE, Reason => ... }` doner. Karar nedeni ic log/audit icindir; dis API adapter'i tenant varligini gostermeyen genel hata mesaji kullanmalidir.

CAT-02 form semasi, uygunluk kurallari, portal render'i ve ceviri icerigini ekleyecektir.
