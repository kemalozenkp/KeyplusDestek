# Keyplus Destek

Windows remote support client maintained by **Keyplus Yazılım Donanım Danışmanlık Ltd Şti**. Contact: **info@keyplus.com.tr**.

This public client fork is based on [RustDesk 1.5.3](https://github.com/rustdesk/rustdesk/tree/95cca3f661f635b3cc85c04935fe8d96d8f432ef). Original source and copyright notices are preserved. See [upstream README](README.upstream.md) and [AGPL licence](LICENCE).

**SignPath application preparation: not accepted and no signed release is available from this repository yet.** The current Keyplus Destek release is unsigned.

[Project, download and source information](keyplus-destek/signpath/README.md) · [Code signing policy](keyplus-destek/signpath/CODE_SIGNING_POLICY.md) · [Privacy disclosure draft](keyplus-destek/signpath/PRIVACY.md)

The Keyplus build kit lives in `keyplus-destek/`. The native build workflow checks out the pinned RustDesk source, applies this kit and runs native/Flutter tests. The package workflow consumes the successful native artifact and tests extraction, installation and upgrade on an isolated Windows runner. Run `node --test keyplus-destek/test/*.test.mjs` for build-kit regression tests. Public build evidence and SignPath onboarding remain pending.
