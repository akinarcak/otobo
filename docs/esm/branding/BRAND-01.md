# CareOnCloud ESM marka ve altyapı göçü

## Hedef durum

- Ürün adı: `CareOnCloud ESM`
- Uygulama yolu: `/careoncloud`
- Statik içerik yolu: `/careoncloud-web`
- Kurulum dizini: `/opt/careoncloud`
- Veritabanı ve uygulama kullanıcısı: `careoncloud_esm`
- Docker servis/volume öneki: `careoncloud`
- Kaynak şemaları: `careoncloud-schema.xml` ve `careoncloud-initial_insert.xml`

## Yasal sınır

CareOnCloud ESM, GPL-3.0 kapsamında RotherOSS/otobo kaynak kodundan türetilmiştir. Upstream telif ve lisans bildirimleri kaynak dosyalardan silinmez. Ürün arayüzünde upstream marka kullanılmaz; köken bilgisi GitHub README ve NOTICE dosyasında tutulur.

## Göç sırası

1. Yeni adlar ve yollar kanonik olarak tanımlanır.
2. Mevcut veritabanı ve Docker volume verileri yedeklenir.
3. Veriler yeni veritabanı, kullanıcı ve volume adlarına kopyalanır.
4. Uygulama yeni `/opt/careoncloud` dizini ve `/careoncloud` URL'iyle doğrulanır.
5. Eski URL/yol uyumluluk takma adları yalnızca doğrulama tamamlandıktan sonra kaldırılır.

## Kabul ölçütleri

- Arayüz, e-posta, API ve dokümanlarda yalnızca CareOnCloud ESM görünür.
- Çalışan yapılandırma `careoncloud_esm` veritabanını kullanır.
- Docker kalıcı verileri CareOnCloud adlı volume'larda bulunur.
- Eski marka adı sadece GPL/telif bildirimi, NOTICE/README köken atfı ve süreli göç kodunun kontrollü izin listesinde kalır.
- Tam test paketi ve demo kabul senaryoları başarılıdır.

## Canlı veri göçü

`development/d724/migrate-careoncloud-brand.sh` eski veritabanı ve Docker volume'larını silmeden kopyalar. Betik varsayılan olarak yalnızca planı gösterir; `--execute` için eski volume adı ve yeni veritabanı parolası açıkça verilmelidir.

Örnek ön izleme:

```bash
development/d724/migrate-careoncloud-brand.sh \
  --old-app-volume mevcut_otobo_app \
  --old-update-volume mevcut_otobo_update
```

Gerçek göçten önce volume adları `docker volume ls` ile doğrulanmalı ve betiğin oluşturduğu SQL dump çalışma alanı dışında güvenli bir yedeğe kopyalanmalıdır. Eski veritabanı ve volume'lar kabul testleri tamamlanmadan kaldırılmaz.
