# CareOnCloudFoundation

`CareOnCloudFoundation` is the first installable CareOnCloud ESM package. It owns product identity, edition metadata, privacy-safe defaults and foundation diagnostics. It intentionally contains no ticket workflow or tenant data model; those capabilities belong to later packages.

## Build

From a CareOnCloud ESM runtime containing this source directory:

```bash
mkdir -p /tmp/careoncloud-package-out
bin/careoncloud.Console.pl Dev::Package::Build \
  --module-directory packages/CareOnCloudFoundation \
  packages/CareOnCloudFoundation/CareOnCloudFoundation.sopm \
  /tmp/careoncloud-package-out
```

The result is `CareOnCloudFoundation-0.1.0.opm`.

## Install and verify

```bash
bin/careoncloud.Console.pl Admin::Package::Install /tmp/careoncloud-package-out/CareOnCloudFoundation-0.1.0.opm
bin/careoncloud.Console.pl Admin::CareOnCloud::FoundationStatus --json
bin/careoncloud.Console.pl Dev::UnitTest::Run --test scripts/test/CareOnCloud/Foundation.t
bin/careoncloud.Console.pl Dev::UnitTest::Run --test scripts/test/CareOnCloud/FoundationStatus.t
```

All package code is licensed under GPL-3.0-only. The edition setting describes the support and operations contract; it does not change the software license.
