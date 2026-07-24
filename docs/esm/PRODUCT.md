# Urun Tasarimi

## Konumlandirma

D724 ESM, kurumsal hizmetleri tek katalog ve tek sorumluluk modeli uzerinde yoneten, MSP kullanimi icin de uygun, acik kaynak bir Enterprise Service Management platformudur. Hedef; ServiceNow'un genisligini veya 4me'nin olgunlugunu ilk gunden kopyalamak degil, en sik kullanilan isleri daha hizli kurulan ve daha seffaf bir urunde birlestirmektir.

## Birincil kullanicilar

- Hizmet alan: katalogdan talep acar, durum ve taahhutleri gorur.
- Uzman/agent: kuyruk, gorev, bilgi ve varlik baglaminda calisir.
- Hizmet sahibi: katalog, maliyet, SLA/OLA ve iyilestirme verisini yonetir.
- Platform yoneticisi: tenant, kimlik, yetki, otomasyon ve entegrasyon kurar.
- MSP yoneticisi: musteri veri sinirlarini, sozlesmeleri ve ortak ekipleri yonetir.
- Denetci: degistirilemez olay izi ve kanit paketlerini inceler.

## Moduller

### P0 - satilabilir cekirdek

1. Omnichannel case ve request yonetimi: portal, e-posta, API ve webhook.
2. Hizmet katalogu: hizmet, teklif, form, onay, fulfillment plani ve maliyet.
3. SLA/OLA: calisma takvimi, duraklatma kurali, ihlal tahmini ve eskalasyon.
4. Incident, major incident, service request, problem ve knowledge.
5. Basit CMDB/asset baglami: hizmet-CI-kisi-sozlesme iliskileri.
6. Coklu organizasyon/MSP izolasyonu: musteri, ekip ve veri erisim politikalari.
7. SSO/MFA baglanti noktasi, rol tabanli yetki ve denetim izi.
8. Yonetici panolari: backlog, SLA, ilk temas cozumu, yeniden acilma ve memnuniyet.

### P1 - ESM genislemesi

- Change enablement ve CAB takvimi
- HR onboarding/offboarding hizmet paketi
- Facilities ve saha hizmeti
- Tedarikci, sozlesme ve entitlement yonetimi
- Proje/portfoy hafif gorunumu
- Mobil uyumlu agent ve onay deneyimi
- Gelismis servis maliyeti ve showback

### P2 - akilli platform

- Talep siniflandirma, ozetleme ve cozum onerisi
- Bilgi makalesi taslagi ve bilgi boslugu tespiti
- Benzer olay/kok neden iliskilendirmesi
- SLA ihlal riski ve is yuku tahmini
- Dogal dille katalog ve rapor sorgusu
- Arac kullanan, sinirli yetkili otomasyon ajanlari

Yapay zeka ozellikleri tenant bazinda kapatilabilir; kisisel veri maskeleme, model/istem surumleme, kaynak baglantisi, guven skoru, maliyet limiti ve insan onayi zorunlu urun yetenekleridir. Musteri verisi varsayilan olarak model egitiminde kullanilmaz.

## Fark yaratan urun sozleri

- 30 dakikada ilk hizmet katalogu, 1 gunde ilk departman.
- Her kayitta "kim, ne zaman, hangi taahhutle" gorunumu.
- Cekirdek ekranlarda eklenti gerektirmeyen Turkce deneyim.
- MSP icin tek konsolda kesin veri sinirlari ve musteri bazli SLA.
- Acik API, disari aktarilabilir veri ve belgelenmis veri modeli.

## MVP kabul olcutleri

- Portal talebi e-posta ve API ile ayni case modelinde ilerler.
- Bir talep cok adimli onay ve paralel fulfillment gorevleri calistirir.
- SLA, calisma takvimine gore dogru hesaplanir ve ihlal oncesi eskalasyon uretir.
- Agent yalnizca yetkili oldugu organizasyonun kayitlarini gorur.
- Her durum/yetki/atama degisikligi denetim olayina donusur.
- Yedekten geri donus, upstream guncelleme ve tenant disari aktarimi belgelenir.
