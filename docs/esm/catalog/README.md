# CareOnCloud ESM Hizmet Kataloğu

Kaynak doküman: **Careon Hizmet Kataloğu — DD-YHE-02-R1 (DORA uyumlu konsolide sürüm)**.

Katalog, portalda gezilebilir üç katmanlı bir yapıya dönüştürülür:

- **Hizmet:** İzleme, Sistem ve Altyapı, Bulut ve Platform, Ağ, Siber Güvenlik, Profesyonel Hizmetler.
- **Hizmet sunumu:** Kaynak dokümandaki numaralı yönetilen hizmet bileşeni.
- **Katalog öğesi:** Onay, uygulama adımları, SLA/OLA bağlantısı ve dinamik talep formu bulunan müşteri talebi.

İçe aktarıcı `development/careoncloud/Seed-CareOnCloudManagedServicesCatalog.pl` tekrar çalıştırılabilir. Varsayılan olarak ana demo tenant'ı ile üç sentetik sektör tenant'ına 51 katalog öğesi ekler. Gerçek müşteri referansı oluşturmaz.

Her talep formu talep türü, iş kritikliği, etkilenen varlık, iş etkisi, hedef tarih ve isteğe bağlı DORA/denetim referansı toplar. İş akışı tenant yöneticisi onayı, risk/kapsam değerlendirmesi ve uygulama/doğrulama adımlarını içerir.

DORA uyumu ürün veya tedarikçi tarafından tek başına garanti edilmez. Katalog; ICT risk yönetimi, olay izlenebilirliği, dijital operasyonel dayanıklılık testleri ve üçüncü taraf risk yönetimi için kanıt üretimini destekleyen bir kontrol çerçevesidir.
