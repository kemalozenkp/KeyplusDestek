# Keyplus Destek

Status: **preparation only; not accepted by SignPath Foundation and not signed**.

Applicant: **Keyplus Yazılım Donanım Danışmanlık Ltd Şti**

Contact: **info@keyplus.com.tr**

Project: **Keyplus Destek**, a Windows remote support application derived from
[RustDesk](https://github.com/rustdesk/rustdesk), distributed under AGPL-3.0.

This preparation is separate from Keyplus ERP. Only the client source,
its build instructions, licence, artwork, public connection configuration,
and client documentation are candidates for publication. ERP source,
repository history, customer data and operational credentials are outside it.

## Existing release

- Release: `2026.11.21.1`, native version `1.5.3`, Windows x64.
- [Windows download](https://portal.keyplus.com.tr/downloads/keyplus-destek/KeyplusDestek.exe)
- [Corresponding source](https://portal.keyplus.com.tr/downloads/keyplus-destek/KeyplusDestek-source.tar.gz)
- [Release manifest](https://portal.keyplus.com.tr/downloads/keyplus-destek/release.json)
- [SHA-256 checksums](https://portal.keyplus.com.tr/downloads/keyplus-destek/SHA256SUMS.txt)
- Current Authenticode status: **NotSigned**. A source archive or checksum is
  not a substitute for an approved signing request.

## Source provenance and public repository

The client is based on RustDesk commit
`95cca3f661f635b3cc85c04935fe8d96d8f432ef` (tag `1.5.3`), with
`hbb_common` commit `fae47e024dd83cef6aaecde0aa7d11731df11649`.
Original licences and copyright notices must remain intact.

The client repository is [kemalozenkp/KeyplusDestek](https://github.com/kemalozenkp/KeyplusDestek),
a separate public fork of RustDesk. Its `keyplus-main` branch is based on the
pinned upstream source and contains only client-related additions. The
original private ERP development repository is not part of this fork.

The supplied build workflows check out the pinned upstream and apply the
Keyplus templates before compiling. A public build from the new repository
must pass before it can be presented as SignPath build provenance. Existing
private build results are historical evidence, not an approved SignPath build.

## Code signing policy

See [Code signing policy](CODE_SIGNING_POLICY.md). This is the policy being
prepared for application, not a claim of active sponsorship.

## Privacy and contact

See [privacy disclosure draft](PRIVACY.md). The runtime relay configuration
and unattended-access behavior must be disclosed accurately during review.

## Remaining external steps

1. Run the public native build and publish source-linked evidence.
2. Confirm the responsible GitHub/SignPath accounts, MFA, branch review and
   release-approval settings; these were not verified by this preparation.
3. Finalize the privacy disclosure and its presentation to users.
4. Submit the organization application at <https://signpath.org/apply>.
5. If accepted, configure the organization/project/policies, trusted GitHub
   integration and allowed artifacts with SignPath. Actual values must come
   from the approved account; no fabricated organization ID or token is used.
6. Sign our native EXE and native DLL before packaging, then sign the portable
   wrapper. Recompute inventories and rerun extraction/install/upgrade tests
   against the signed bytes before publishing any signed release.

The Foundation decides eligibility, including the suitability of this fork
and its verifiable reputation. Acceptance and response time are not guaranteed.

References: [Foundation terms](https://signpath.org/terms),
[GitHub integration](https://docs.signpath.io/trusted-build-systems/github).
