# CI / CD Pipeline

Production-oriented GitHub Actions layout for Look After.

## Workflows

| Workflow | File | When | Purpose |
|----------|------|------|---------|
| **CI** | `ci.yml` | PR + push main + manual | Fast gate: lint, package tests, build, EVP tier-2, smoke UI |
| **Nightly** | `nightly.yml` | 07:00 UTC daily + release/* | Full matrix: visual, perf, a11y, replay, counterfactual, budgets |
| **Security** | `security.yml` | PR/push + weekly | Gitleaks, dependency review, CodeQL, SBOM, SPM audit |
| **Release** | `release.yml` | release/*, tags v*.*.*, manual | EVP release gate, changelog, optional TestFlight |
| **EVP legacy** | `executive-validation.yml` | manual only | Monolithic full EVP escape hatch |

## Composite actions

- `.github/actions/setup-ios` — Xcode, SPM cache, XcodeGen, Firebase stub, DESTINATION env
- `.github/actions/build-evp` — build EVP CLI as ./evp

## Branch protection (recommended)

Require on `main`:

1. CI / CI gate
2. Security / Gitleaks
3. Security / Dependency review (PRs)

On `release/*` also require:

4. Release / EVP release gate

## Secrets

| Secret | Used by | Required |
|--------|---------|----------|
| CODECOV_TOKEN | CI, Nightly | Optional |
| GITLEAKS_LICENSE | Security orgs | Optional |
| BUILD_CERTIFICATE_BASE64 | Release TestFlight | Optional |
| P12_PASSWORD | Release | With cert |
| KEYCHAIN_PASSWORD | Release | With cert |
| PROVISION_PROFILE_BASE64 | Release | With cert |
| APP_STORE_CONNECT_API_KEY_ID | TestFlight | Optional |
| APP_STORE_CONNECT_API_ISSUER_ID | TestFlight | Optional |
| APP_STORE_CONNECT_API_KEY_BASE64 | TestFlight | Optional |
| EXPORT_OPTIONS_PLIST | Export IPA | Optional |

## Observability

- Artifacts with retention 7-90 days
- dorny/test-reporter for JUnit check annotations
- Nightly budget gate fails only on catastrophic >2x regressions
- EVP github-summary.md into step summary

## Local parity

```bash
swiftlint lint
swift test --package-path Packages/LookAfterCore --parallel
swift build --package-path Tools/ExecutiveValidationPlatform -c release
ln -sfn "$(swift build --package-path Tools/ExecutiveValidationPlatform -c release --show-bin-path)/evp" ./evp
./evp index && ./evp run --tier 2 --skip-ui && ./evp decisions
```

## SwiftLint

Baseline `.swiftlint.yml` keeps force_cast as warning and large length rules off.
Flip CI to `--strict` once debt is paid.
