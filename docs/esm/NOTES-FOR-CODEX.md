# Codex icin devir notu: release image build "takilmasi" vakasi

**Tarih:** 4 Agustos 2026
**Branch:** `codex/esm-foundation`
**Konu:** `.github/workflows/careoncloud-release.yml` build adiminin "ilerleme uretmeden takildigi" teshisi
**Sonuc:** Teshis yanlisti. Build hicbir zaman takilmadi. Tam release zinciri degistirilmemis workflow ile CI'da tamamlandi.

---

## 1. Ozet

Bes ardisik run'da build adiminin "takildigi" raporlandi ve her biri iptal edildi. Gercekte
build adimi **her seferinde saglikli ilerliyordu** ve normal suresi olan ~7 dakikanin
altinda kesildi.

Workflow'a **hicbir degisiklik yapmadan**, sadece iptal etmeden calistirildiginda tam zincir
`success` verdi:

> Run [30824056768](https://github.com/akinarcak/otobo/actions/runs/30824056768) — toplam 9dk55sn
> build/push -> SBOM -> artifact upload -> Cosign keyless OIDC imzasi

---

## 2. Kok neden: run seviyesindeki `updatedAt` bir ilerleme gostergesi degildir

Teshis, GitHub Actions API'sindeki run nesnesinin `updatedAt` alaninin degismemesine
dayandirilmisti.

**Bu alan, tek bir adim uzun sure calisirken tick etmez.** Yalnizca adim gecislerinde
guncellenir. Dolayisiyla:

- `updatedAt` sabit  ==  "tek adim hala calisiyor"
- `updatedAt` sabit  =/=  "takildi"

Ayni sekilde `gh run view --log` **tamamlanmamis** bir run icin log dondurmez; bu da
"log uretmiyor" izlenimini guclendirdi. Calisan bir adimin ciktisini gormek icin
web UI'daki canli log akisi veya `gh run view --log` **run bittikten sonra** kullanilmalidir.

### Iptal anindaki gercek durumlar

Iptal edilen run'larin son log satirlari, hepsinin ilerlemekte oldugunu gosteriyor:

| Run | Build adimi suresi | Iptal anindaki gercek durum |
|---|---|---|
| 30820150916 | 6dk16sn | **Build bitmis**, image push %72: `#27 pushing layer 1.03GB / 1.43GB` |
| 30820904874 | — | `Cache export is not supported for the docker driver` (kendi kendine acilan hata) |
| 30821129445 | 3dk22sn | CPAN kurulumu ilerliyordu |
| 30821523907 | — | `Unexpected input(s) 'progress'` |
| 30821704656 | 1dk29sn | `#16 25.97 Successfully installed DBI-1.651` |
| **30824056768** | **7dk04sn** | **Kesilmedi -> `success`** |

`30820150916` ozellikle onemli: hicbir "duzeltme" yapilmamis **ilk** run'di ve image'i
GHCR'a iterken, 1.43 GB'in 1.03 GB'i gitmisken iptal edildi. Bitmesine muhtemelen
1-2 dakika kalmisti. Yani sorun daha ilk denemede yoktu.

### Bagimsiz corroborating kanit

Ayni gun, ayni tip runner'da gecen foundation run [30817232194](https://github.com/akinarcak/otobo/actions/runs/30817232194)
icindeki `Accept clean D724 package lifecycle` adimi **8dk15sn** surdu, `careoncloud.web.dockerfile`'i
**basariyla build etti** ve bir sonraki adim ("Scan built CareOnCloud image") o image'i tarayip gecti.

Yani Dockerfile'in GitHub Actions runner'inda tek uzun adim olarak ~8 dakikada sorunsuz
build oldugu, release workflow'undan bagimsiz olarak zaten kanitlanmisti.

---

## 3. Teshisi kendini besleyen donguye ceviren ikincil mekanizma

`cache-to` export'u build'in **sonunda** calisir.

Her run bitmeden iptal edildigi icin cache **hic yazilamadi** -> her yeni run yine sifirdan
(soguk) basladi -> yine yavas gorundu -> yine iptal edildi.

Eklenen GitHub Actions cache'inin fayda vermemesinin sebebi cache'in kendisi degil,
**hic yazilamamis olmasiydi.** Bu, "cache eklendi ama ise yaramadi, demek ki sorun daha
derinde" seklinde yanlis bir cikarima yol acti.

---

## 4. Yapilan bes "duzeltme"nin degerlendirmesi

Hicbiri var olan bir sorunu hedeflemiyordu:

| Degisiklik | Gercek gerekce | Durum |
|---|---|---|
| `docker/setup-buildx-action` eklendi | `cache-to` eklendigi icin gerekti | Kendi acilan sorunun cozumu |
| GHA cache (`cache-from`/`cache-to`) | Var olmayan yavasligi cozmek icin | Faydali ama sorunun sebebi degildi |
| `pull: true` | — | Notr |
| `progress` input | Desteklenmeyen input, run'i bozdu | Geri alindi |
| `DOCKER_TAG` explicit build-arg | — | **Zararli, bkz. bolum 6** |

`Cache export is not supported for the docker driver` hatasi da dahil olmak uzere, sonradan
cozulen hatalarin bir kismi **ilk teshisin kendisi tarafindan yaratilmisti.**

---

## 5. Kanitlanmis release zinciri

Run `30824056768`, `workflow_dispatch` ile `codex/esm-foundation` uzerinde, workflow
**degistirilmeden** calistirildi (deneyi kirletmemek icin yeni commit/tag olusturulmadi).

| Adim | Sure | Sonuc |
|---|---|---|
| Build and push CareOnCloud image | 7dk04sn | `success` |
| Generate SPDX SBOM | 1dk57sn | `success` |
| Upload SBOM | 2sn | `success` |
| Install Cosign | 1sn | `success` |
| Sign immutable image by keyless OIDC | 4sn | `success` |

Artefaktlar:

- **Image digest:** `sha256:e6075fb47fc43e085c703822745a9356f402499ea6dd99571a0df058a8239255`
- **Push hedefi:** `ghcr.io/akinarcak/otobo/careoncloud:v0.0.0-probe.e82d348c1`
- **SBOM artifact:** `careoncloud-sbom-v0.0.0-probe.e82d348c1`, 1.287.359 bayt, `expired=false`
- **Cosign:** v2.5.0 keyless OIDC, `tlog entry created with index: 2335222741`,
  `Pushing signature to: ghcr.io/akinarcak/otobo/careoncloud`

Rekor transparency log kaydi (`2335222741`) imzanin bagimsiz dogrulanabilir kanitidir.

Gercek build suresi ~7 dakika; workflow'daki `timeout-minutes: 45` limitine yaklasilmadi bile.
195 CPAN dagitimi / 648 modul kuruluyor, bu sure normaldir.

---

## 6. Ayri bulgu: `DOCKER_TAG` build-arg'i

"Explicit build arg" olarak eklenen `DOCKER_TAG=careoncloud-${{ steps.tag.outputs.tag }}`
degeri, Dockerfile'da pahali `carton install` RUN'indan **hemen once** tuketiliyor
(`careoncloud.web.dockerfile`, `ARG DOCKER_TAG=unspecified`).

Deger her release'te degistigi icin CPAN katmaninin cache anahtarini bozma riski tasir.

Ustelik **hicbir islevsel fayda saglamaz**: Dockerfile'daki tek kullanimi
`if [[ $DOCKER_TAG == local-* ]]` kosuludur; varsayilan deger `unspecified` zaten
`local-*` desenine uymaz ve istenen `carton install --deployment` yoluna girer.

### Olcum (varsayim degil)

Ayni commit, ayni workflow, yalnizca image tag'i farkli iki run:

| Run | Tag | `DOCKER_TAG` | Build adimi | `base 7/7` (`carton install`) |
|---|---|---|---|---|
| 30824056768 | probe | var | 7dk04sn | miss (soguk cache) |
| 30882609007 | probe2 | var | 4dk45sn | **miss** — 213 dagitim, 211.9sn |
| 30883159985 | probe3 | **yok** | 4dk50sn | miss (yeni anahtar, cache yazildi) |
| 30883550612 | probe4 | **yok** | **9 saniye** | **CACHED** — 0 kurulum |

`30882609007` calisirken `base 1/7` ... `base 6/7` katmanlarinin hepsi `CACHED` raporlandi;
cache hit tam olarak ARG'i tuketen katmanda kesildi. Bu, build-arg'in sucunu tek basina
kanitlar.

`30883550612`'nin tag'i `30883159985`'ten **farklidir**. Eskiden bu tek basina CPAN
katmanini bozmaya yetiyordu; artik yetmiyor.

### Alinan aksiyon

Commit `41fc6a9b1` build-arg'i kaldirdi. Build+push 7dk04sn -> 9sn, tam zincir
9dk55sn -> 1dk32sn. Zincir yine `success` verdi; imza yolu zayiflamadi.

`Test-CareOnCloudReleaseWorkflow.ps1` artik `DOCKER_TAG=` yeniden eklenirse fail eden
bir regression guard tasiyor.

---

## 7. Bir daha tekrarlanmamasi icin kurallar

1. **Bir CI adimini, o adimin bilinen normal suresini bilmeden iptal etme.**
   Bu image icin referans: build+push ~7 dk, tam zincir ~10 dk.

2. **`updatedAt` alanini ilerleme gostergesi olarak kullanma.** Uzun tek adimlarda tick etmez.
   Ilerleme icin web UI canli log akisini kullan, ya da adim `startedAt` degerinden gecen
   sureyi hesapla.

3. **`gh run view --log` calisan run icin bos doner.** Bu "log uretmiyor" demek degildir.

4. **`timeout-minutes` zaten bir guvenlik agidir.** 45 dakikalik limit varken adimi
   2 dakikada elle kesmek, guvenlik agini devre disi birakip yerine daha kotu bir
   sezgi koymaktir. Runner tuketimi endisesi varsa cozum `timeout-minutes` degerini
   dusurmektir, elle iptal degil.

5. **Bir "duzeltme" uygulamadan once, teshisi yanlislayabilecek en ucuz deneyi yap.**
   Burada o deney "workflow'u degistirmeden bir kez sonuna kadar calistirmak"ti ve
   ~10 dakika surerdi. Bunun yerine bes ayri degisiklik yapildi ve bir kismi yeni
   hatalar uretti.

6. **Degisiklik yaparken deneyi kirletme.** Kok neden dogrulanmadan once workflow'a
   dokunmak, sonucun hangi degisikligeden geldigini belirsizlestirir. Once degistirilmemis
   haliyle olc, sonra tek degisken degistir.

---

## 8. Uretim dokunulmadi

Bu calismada yalnizca `workflow_dispatch` ile aday (`probe`) tag'leri kullanildi.
Uretim servisleri, canli cutover, `d724-esm-*` container/volume'lari ve Yetka verileri
degistirilmedi. GHCR'a yalnizca `v0.0.0-probe*` etiketli aday image'lar itildi.

---

## 9. Codex icin acik isler

Asagidakiler bilerek karara baglanmadi. Kapsam disi olduklari veya urun/politika karari
gerektirdikleri icin sana birakiliyor.

### 9.1 Karar gerektirenler

**`CAREONCLOUD-ESM-AI-MASTER-CONTEXT.md` versiyonlanmiyor.**
Dosya calisma agacinda hem kokte hem `docs/esm/` altinda **untracked** duruyor. Iki kopya var
ve icerikleri ayni degil. Kendi basima repoya eklemedim; hangisinin kanonik oldugu ve Git'e
girip girmeyecegi urun karari. Karar verilene kadar bu dosyaya yapilan degisiklikler
kaybolmaya aciktir.

**GHA cache boyutu izlenmiyor.**
`cache-to: type=gha,mode=max` butun ara katmanlari export eder. GitHub Actions cache'i
repo basina 10 GB ile sinirlidir ve doldugunda LRU ile tahliye edilir. Bu image icin
katmanlar buyuk. Eger cache surekli tahliye ediliyorsa `mode=min` veya GHCR'a
`type=registry` cache daha uygun olabilir. Simdilik `mode=max` birakildi cunku olculmedi;
tahliye gozlenirse olcup degistir.

### 9.2 Kodda gorulen, dokunulmayan kusurlar

**`careoncloud-web` stage'inde image version label'i bos kaliyor.**
`careoncloud.web.dockerfile` icinde `ARG DOCKER_TAG` yalnizca `base` stage'inde
tanimlanmis. ARG'lar `FROM` sinirini gecmez ve `careoncloud-web` stage'i onu yeniden
tanimlamiyor, ama satir sonunda `LABEL org.opencontainers.image.version=$DOCKER_TAG`
kullaniyor. Yani bu label ureten imajlarda bostur. `careoncloud-web-kerberos` stage'i
ise ARG'i dogru sekilde yeniden tanimliyor; tutarsizlik burada.

Duzeltmek istersen: `ARG DOCKER_TAG=unspecified` satirini `careoncloud-web` stage'inin
**sonuna**, LABEL'lardan hemen once ekle. Oraya konursa yalnizca ucuz LABEL katmanini
etkiler, pahali CPAN katmanina dokunmaz. Bu bolum 6'daki hatanin tekrari **degildir** —
kritik olan ARG'in nerede tuketildigidir, sadece tanimlandigi yer degil.

Bu bir provenance eksigidir; release imajlari surumlerini label'dan bildirmiyor.
Kapsam disi biraktim cunku paylasilan Dockerfile'a dokunuyor.

**SBOM adim adi ile ciktisi uyusmuyor.**
`.github/workflows/careoncloud-release.yml` icindeki adim `Generate SPDX SBOM` adini
tasiyor ama `format: cyclonedx-json` ile CycloneDX uretiyor ve dosyayi `.cdx.json` olarak
yaziyor. Cikti dogru, ad yaniltici. Uyumluluk dokumantasyonunda "SPDX SBOM uretiliyor"

**Durum (4 Agustos 2026):** Workflow adimi `Generate CycloneDX SBOM` olarak yeniden
adlandirildi; `format: cyclonedx-json` ile uyumlu isimlendirme commit `02a8de71c` ile
push edildi. Cikti formatinda degisiklik yoktur.

## GHA cache olcumu (4 Agustos 2026)

GitHub cache API olcumu: 44 aktif cache, toplam 1.319 GiB (1,415,847,893 byte).
BuildKit girdileri 37 cache / 0.952 GiB. En eski BuildKit girdisi 2026-08-03 14:49:39Z,
en yeni 2026-08-04 06:19:02Z. Mevcut footprint 10 GiB repo limitinin altinda; tahliye
belirtisi yok. Bu nedenle `mode=min` veya registry cache gecisi icin kanit yok. Release
oncesi footprint yeniden olculmeli.
denmesi riskini tasir. Adi duzeltmek yeterli.

### 9.3 Hala acik olan release kapilari

Bunlar bu calismada **tamamlanmis sayilmadi** ve oyle raporlanmamalidir:

- Gercek `careoncloud-v*` imzali release tag'i (yalnizca `v0.0.0-probe*` aday tag'leri
  calistirildi)
- Canli Cloudflare cutover'i ve rollback provasi
- Uretim kabulu
- `/careoncloud/` canonical yolunun canli origin'de dogrulanmasi (aday portta gecti,
  canlida `/otobo/` hala 200 donuyordu)

Kanitlanan sey **release mekanizmasidir**, bir release degil.

### 9.4 Uretim durumu

Bu calismada uretim servisleri, `d724-esm-*` container/volume'lari ve Yetka verileri
degistirilmedi. GHCR'a yalnizca `v0.0.0-probe*` etiketli aday imajlar itildi. Bunlar
temizlenebilir; kalici bir release degildirler.

### 9.5 Guncel probe (4 Agustos 2026)

Run `30886247537` (commit `2123426a0`) guncel image label ve CycloneDX SBOM
adlandirmasi ile basarili oldu. Build/push 9 saniye cache hit, SBOM 60 saniye,
artifact upload ve Cosign keyless imza basariliydi. Probe image digest'i
`sha256:7c999567722ca3847f1cd5104c015173dbb1584b51106075cacc8d0e16c664d9`, Rekor
index `2339281679`. Bu probe tag'idir; gercek release veya canli cutover degildir.

### 9.6 Gercek imzali release (4 Agustos 2026)

`careoncloud-v0.1.0` etiketiyle run `30886590617` basarili oldu. Image digest'i
`sha256:7c1091f92d168e9e4980eedb8156d9c9be07cd4cffcb0a0fe78b55fe72938b44`, SBOM
artifact'i `careoncloud-sbom-v0.1.0` (1,287,333 byte, ID `8883513965`), Rekor
index `2339297418`. Bu, ilk gercek imzali release image'idir; canli cutover ve
rollback ayri kontrollu adimlar olarak kalir.
