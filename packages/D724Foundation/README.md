# D724Foundation

`D724Foundation` is the first installable D724 ESM package. It owns product identity, edition metadata, privacy-safe defaults and foundation diagnostics. It intentionally contains no ticket workflow or tenant data model; those capabilities belong to later packages.

## Build

From an OTOBO runtime containing this source directory:

```bash
mkdir -p /tmp/d724-package-out
bin/otobo.Console.pl Dev::Package::Build \
  --module-directory packages/D724Foundation \
  packages/D724Foundation/D724Foundation.sopm \
  /tmp/d724-package-out
```

The result is `D724Foundation-0.1.0.opm`.

## Install and verify

```bash
bin/otobo.Console.pl Admin::Package::Install /tmp/d724-package-out/D724Foundation-0.1.0.opm
bin/otobo.Console.pl Admin::D724::FoundationStatus --json
bin/otobo.Console.pl Dev::UnitTest::Run --test scripts/test/D724/Foundation.t
bin/otobo.Console.pl Dev::UnitTest::Run --test scripts/test/D724/FoundationStatus.t
```

All package code is licensed under GPL-3.0-only. The edition setting describes the support and operations contract; it does not change the software license.
