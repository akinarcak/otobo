# D724 Prometheus operasyon yuzeyi

`D724Observability 0.1.0`, tenant kimligi veya PII icermeyen 20 sabit metrik
serisini OTOBO Public frontend uzerinden sunar:

```text
GET /careoncloud/public.pl?Action=PublicD724Metrics
Authorization: Bearer <scrape-token>
```

Tokenin kendisi SysConfig'e yazilmaz. Yalniz kucuk harfli 64 karakter SHA-256
digest'i `D724::Observability::MetricsTokenSHA256` ayarinda saklanir. Ayar bos,
gecersiz veya observability kapaliysa endpoint `503`; eksik/yanlis Bearer icin
`401`; basarili scrape icin `200` doner. Yanit `no-store`, `nosniff` ve Prometheus
0.0.4 content type basliklarini tasir.

Token uretme ve ayarlama ornegi (secret manager ile uygulanmalidir):

```text
token=<secret-manager-generated-value>
digest=<sha256(token)>
bin/careoncloud.Console.pl Admin::Config::Update --setting-name D724::Observability::MetricsTokenSHA256 --valid 1
bin/careoncloud.Console.pl Admin::Config::Update --setting-name D724::Observability::MetricsTokenSHA256 --value <digest>
```

`--valid` ve `--value`, OTOBO komutunun birbirini dislayan islem kipleri oldugu
icin iki ayri komuttur. Token komut satirina, repoya veya loga konulmamalidir.

## Kardinalite ve veri siniri

- Metrik adlari kod icindeki allow-list ile sabittir; dinamik label yoktur.
- Tenant, kullanici, requester, rota, request ID, ticket ID ve serbest metin export edilmez.
- API 5 dakikalik hacim/error/latency, webhook backlog/age/dead-letter,
  commitment/escalation, Elasticsearch tenant policy ve tenant-cache sinyalleri vardir.
- `d724_up`, sorgular ve zorunlu koruma katmanlari calisiyorsa `1` olur. Domain
  alarm durumlari ayri `d724_alert_*` serileridir; alarm olmasi exporter'i down yapmaz.
- Veri sorgusu hatasi veya zorunlu tablo/koruma eksigi HTTP scrape'i `503` ile
  fail-closed yapar; konsol JSON'u tani icin ayrintili sayaclari dondurur.

## Prometheus scrape ornegi

```yaml
scrape_configs:
  - job_name: d724-esm
    metrics_path: /careoncloud/public.pl
    params:
      Action: [PublicD724Metrics]
    authorization:
      type: Bearer
      credentials_file: /run/secrets/d724_metrics_token
    static_configs:
      - targets: [d724-web:5000]
```

Internet uzerinden scrape ancak TLS ve ag allow-list'i ile acilmalidir. Test
ortaminda token `/home/test/.d724-metrics-token` dosyasinda `0600` yetkisiyle
tutulur; urun ortaminda platform secret store kullanilmasi zorunludur.

Kabul kapisi:

```text
D724_METRICS_TOKEN=<secret> perl development/d724/Accept-ObservabilityRuntime.pl <url>
```

Bu kapı eksik/yanlis/dogru token icin `401/401/200`, content type, cache
yasagi, secret sizintisi olmamasi, dinamik label bulunmamasi ve tam 20 seri
kosullarini dogrular.
