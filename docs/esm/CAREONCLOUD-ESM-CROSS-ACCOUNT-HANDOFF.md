# CareOnCloud ESM — Hesaplar Arası Tek Devir Dosyası

**Devir tarihi:** 2026-08-03
**Repo:** `https://github.com/akinarcak/otobo`  
**Çalışma dalı:** `codex/esm-foundation`  
**Durum:** Geliştirme prototipi; üretime hazır değildir.

Bu dosya, başka bir ChatGPT hesabında projeye devam etmek için tek giriş noktasıdır. Önce ana talimatı okuyun:

`D:\Projects\D724 ESM\docs\esm\CAREONCLOUD-ESM-AI-MASTER-CONTEXT.md`

Ana kurallar: aktif test/üretim servislerini değiştirme; aday ortamı ayrı tut; runtime kanıtı olmadan üretim veya tam izolasyon iddiası yapma; `STATUS.md` ve bu devir dosyasını kanıt seviyeleriyle güncel tut; anlamlı değişiklikleri atomik commit yap; push için ayrıca açık onay al.

## Çalışma alanı ve erişim

- Yerel proje kökü: `D:\Data\Documents\OneDrive - Data Market Bilgi Hizmetleri A.S\Documents\D724 ESM`
- Master context: `D:\Projects\D724 ESM\docs\esm\CAREONCLOUD-ESM-AI-MASTER-CONTEXT.md`
- Test sunucusu: `test@100.86.171.110:22`
- Test sunucusundaki aday kaynak checkout: `/home/test/careoncloud-candidate-shallow-55fd8f3ca`
- GitHub: `akinarcak/otobo`; repo adı ileride değişebilir.
- Windows SSH anahtarı: `C:\Users\Akın Arcak\.ssh\id_ed25519_vps` (private key’i bu dosyaya kopyalamayın).
- Kullanılan PuTTY araçları: `C:\Program Files\PuTTY\plink.exe`, `C:\Program Files\PuTTY\pscp.exe`.

Parola, private key ve GitHub token bu devir dosyasına veya Git’e yazılmayacaktır. Yeni hesapta işletim sistemi Credential Manager/SSH agent/GitHub oturumunu kullanın. Gerekirse kullanıcıdan parola isteyin; dosyada bulunan host/username bilgilerini otomatik parola varsayımı olarak kullanmayın.

## Mevcut kanıt durumu

- Son doğrulanmış kod commit'i: `9ec8f132a fix(esm): preserve ticket cache and merge audit ownership`.
- Çalışma dalı: `codex/esm-foundation`; çalışma ağacı temizdir.
- Tamamlanan son P0 hedefi: D724TicketAudit cache/merge audit ownership düzeltmesi, quick-setup legacy fixture temizliği ve izole aday runtime kabulü.
- Kanıt: D724TicketAudit 4 dosya / 227 test, D724API 6 dosya / 160 test ve D724Reporting 4 dosya / 73 test güncel adayda `PASS`; `Test-Foundation.ps1` mevcut kaynakta `PASS`. Aktif `d724-esm-*` servislerine dokunulmadı.
- Açık sonraki hedef: Kaynak commit'iyle etiketlenmiş yeni image üzerinden tam `Test-CleanPackageLifecycle.ps1` kabulünü tek koşuda çalıştırmak ve aday image provenance'ını son commit'e taşımak.
- `Test-Foundation.ps1` 18 D724 paket manifesti ve dosya listesini geçti.
- CI’de repository dependency Trivy taraması ve temiz lifecycle sonrası `d724/esm:dev` OS/library image taraması tanımlı.
- Temiz lifecycle ve yerel `Build`/`Up` yolları `docker buildx version` önkoşulu ile korunuyor.
- Test sunucusunda Docker Compose 2.40.3 ve kullanıcı-local Docker Buildx 0.34.1 mevcut; güncel aday image üretildi. Eski `d724/esm:dev` image’ı kullanıcı onayıyla kaldırıldı; aktif servisler korunuyor.
- Aktif eski servisler korunmalıdır: `d724-esm-web-1`, `d724-esm-daemon-1`, `d724-esm-db-1`, `d724-esm-redis-1`, `d724-esm-elastic-1`.
- Bu nedenle aşağıdaki iddialar runtime kabulü değildir: eski `d724/esm:dev` imajı, eski volume’lar, tarihsel MariaDB test logları veya yalnız Perl syntax kontrolü.

Kanıt seviyelerini kullanın:

- `VERIFIED_IN_CODE`: kaynakta ve statik kontrolde doğrulandı.
- `VERIFIED_BY_CURRENT_TEST`: mevcut kaynakla ilgili test gerçekten çalıştı.
- `TEST_EXISTS_NOT_RERUN`: test var, güncel adayda yeniden çalışmadı.
- `RISK`: kabul edilmemiş veya kapsamı sınırlı durum.

## Hedef ağacı

### Her modelin uygulayabileceği küçük görevler

1. `git status`, son commit ve `STATUS.md` risklerini kontrol et.
2. Master context’i yeniden oku; aktif servisleri değiştirme sınırını doğrula.
3. Bir dosya/tek kapı kapsamındaki statik düzeltmeyi yap.
4. `powershell -ExecutionPolicy Bypass -File .\development\d724\Test-Foundation.ps1` çalıştır.
5. `git diff --check` çalıştır; sonucu `STATUS.md` kanıt seviyesiyle kaydet.
6. Tek amaçlı atomik commit oluştur; push yapma.
7. Devir dosyasındaki son commit ve durum satırını güncelle.

### Orta seviye model görevleri

- Foundation/brand/language/source-artifact/CPAN-SBOM sözleşmelerini çalıştırmak ve sapmaları düzeltmek.
- D724 paket manifestleri, SOPM sürümleri ve dependency sırasını denetlemek.
- CI workflow YAML’ını statik olarak incelemek; Trivy, Buildx, artifact ve timeout sözleşmelerini korumak.
- `STATUS.md` ve güvenlik kapsamı belgelerindeki tarihsel/abartılı runtime iddialarını düzeltmek.
- Runtime kanıtı yoksa yalnız test hazırlığı yapıp iddiayı `TEST_EXISTS_NOT_RERUN`/`RISK` olarak bırakmak.

### Güçlü model hedefleri

1. BuildKit-capable izole runner sağlamak veya kurulumu doğrulamak; aktif eski Compose projesine dokunmadan güncel commit’ten aday image üretmek.
2. `Test-CleanPackageLifecycle.ps1` çalıştırmak: yeni DB/Redis/app volume, 18 OPM install, unit test döngüsü, Problem uninstall/reinstall ve provenance kontrolü.
3. Gerçek aday MariaDB/HTTP kabulünü çalıştırmak: TicketCreate, TicketUpdate, scheduler pending-check, GenericAgent tenant scope, brand/authenticated UI.
4. Invalid unknown-channel article delete için gerçek fixture ile rollback/audit regression üretmek.
5. Trivy image sonuçlarını incelemek; yalnızca doğrulanmış remediation commit’leri yapmak.
6. Aday image/runtime kanıtını artifact yolları ve commit digest’iyle `STATUS.md` ve bu dosyada güncellemek.
7. Üretim cutover’ı yapmamak; yalnızca kullanıcı ayrıca açıkça onay verirse geçiş planını yürütmek.

## İlk devam oturumu için güvenli sıra

1. Ana master context, `STATUS.md` ve bu dosyayı oku.
2. `git status --short` ve `git log -1 --oneline` ile gerçek durumu doğrula.
3. Test sunucusunda yalnız read-only `docker ps`, `docker version`, `docker compose version`, `docker buildx version`, `df -h /` çalıştır.
4. Buildx yoksa aday lifecycle başlatma; bunu blocker değil, runner hazırlığı olarak kaydet.
5. Buildx varsa ayrı Compose project/volume/port ile aday lifecycle çalıştır; aktif `d724-esm-*` projesine dokunma.
6. Her test sonucu için artifact yolu, commit SHA, kapsam ve kanıt seviyesini yaz.
7. Bir oturumda bir ana hedefi bitir; küçük atomik commit yap.

## Kesinlikle yapılmayacaklar

- `rm -rf` ile workspace, `/home/test`, aktif volume veya belirsiz Docker image silme.
- Aktif `d724-esm-*` konteynerlerini restart/stop/recreate etme.
- `git reset --hard`, force push, rebase veya kullanıcı değişikliklerini silme.
- Private key, parola, token veya session cookie’yi dosyaya/commit’e yazma.
- Eski `d724/esm:dev` imajını CareOnCloud runtime kanıtı olarak kullanma.
- Static test sonucunu authenticated UI, MariaDB transaction veya production readiness kanıtı olarak sunma.

## Handoff güncelleme şablonu

Her oturum sonunda şu alanları güncelleyin:

```text
Son commit: <sha> <mesaj>
Çalışma ağacı: clean/dirty (<neden>)
Tamamlanan hedef: <tek hedef>
Kanıt: <komut veya artifact yolu>
Kanıt seviyesi: VERIFIED_IN_CODE / VERIFIED_BY_CURRENT_TEST / TEST_EXISTS_NOT_RERUN / RISK
Açık sonraki hedef: <tek hedef>
Runner/erişim notu: <Buildx, disk, servis etkisi>
```
