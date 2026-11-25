# Security Frameworks

A native SwiftUI app for iPhone and iPad that helps organizations implement cybersecurity frameworks
one requirement at a time. It works offline and keeps all data on the device.

The project, targets, and code use the working name "FrameworkApp"; the app is published as "Security Frameworks".

**Frameworks at launch:** NIST Cybersecurity Framework 2.0, NIST SP 800-53 Rev. 5 (with SP 800-53B
baselines), and NIST SP 800-171 Rev. 3.

Website: https://cjaratech.com/securityframeworks · Privacy policy: https://cjaratech.com/securityframeworks/privacypolicy

This app is independent and is not affiliated with or endorsed by NIST. It is a self-assessment aid,
not a certification or compliance attestation.

## Repository layout

| Path | What it is |
|---|---|
| `App/` | iOS app target (SwiftUI, Swift 6, iOS 17+) |
| `App/Resources/Content/` | Generated framework content bundled in the app (do not edit by hand) |
| `Packages/FrameworkKit/` | Pure-Swift package: content models, loader, validator, search, scoping, mappings (`FrameworkKit`) and design tokens (`DesignTokens`) |
| `AppTests/`, `AppUITests/` | App unit tests and UI/screenshot tests |
| `tools/oscal_convert/` | Python (standard library only) scripts that fetch NIST sources and generate content |
| `data/sources/` | Pinned NIST source files and their provenance (`SOURCES.json`) |
| `data/editorial/` | Plain-language content written for this app |
| `schema/` | JSON Schemas for the content files |
| `docs/` | [Schema](docs/SCHEMA.md), [content sources and licensing](docs/CONTENT_SOURCES.md), [TestFlight setup](docs/CI_SECRETS.md), [App Store Connect settings](docs/APP_STORE.md), [privacy policy](docs/privacy-policy.md) |
| `project.yml` | XcodeGen project spec; the Xcode project is generated, not committed |

## Content pipeline

```bash
python3 tools/oscal_convert/fetch_sources.py
```

```bash
python3 tools/oscal_convert/convert.py
```

```bash
python3 -m unittest discover -s tools/oscal_convert/tests
```

`fetch_sources.py` re-pins sources to the latest OSCAL commit. Re-run it only when NIST publishes
updates. `convert.py` regenerates `App/Resources/Content`.

## Building

CI on GitHub Actions builds and tests everything on a macOS runner. No local Xcode is needed. On a
Mac with Xcode installed:

```bash
brew install xcodegen
```

```bash
xcodegen generate && open FrameworkApp.xcodeproj
```

Each CI run uploads screenshots of key screens (light, dark, and accessibility text sizes) as the
`screenshots` artifact.
