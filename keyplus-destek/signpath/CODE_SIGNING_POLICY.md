# Code signing policy

Status: **draft for application; no active SignPath signing service**.
Current Keyplus Destek downloads are unsigned.

## Project responsibility

- Project owner and applicant: Keyplus Yazılım Donanım Danışmanlık Ltd Şti.
- Project contact: info@keyplus.com.tr.
- Current technical repository account: [kemalozenkp](https://github.com/kemalozenkp).
- Release approver: a company-authorized maintainer, to be confirmed during
  onboarding. No approver account or MFA status is asserted as verified here.

## Proposed release controls

Sign only source-linked Keyplus Destek builds from the reviewed client
repository. Preserve RustDesk provenance and licences. Require review of
source/build changes and explicit human approval of each signing request.
Protect repository and signing accounts with MFA and limit tokens to the
required project and submission permission.

Sign our native application, our native DLL and our portable wrapper in that
order. Do not re-sign third-party libraries under our project identity.
Verify signatures and timestamping, update hashes, and test the final signed
package before release. The current packaging workflow does not perform these
steps and must not label an unsigned artifact as signed.

## Attribution after acceptance

Only after approval and activation, publish the required attribution:

> Free code signing provided by SignPath.io, certificate by SignPath Foundation

The certificate publisher would be SignPath Foundation. The applicant and
project operator remain the company named above.

Source: [SignPath Foundation terms](https://signpath.org/terms).
