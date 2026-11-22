# Architecture

## Layers

```
NIST OSCAL + CPRT ──fetch_sources.py──▶ data/sources/ (pinned, hashed)
                                            │
data/editorial/ (plain-language overlay) ───┤
                                            ▼
                                  convert.py (validate + lint)
                                            │
                                            ▼
                           App/Resources/Content/*.json (bundled)
                                            │
                                            ▼
          FrameworkKit (pure Swift): FrameworkStore actor → Framework, SearchIndex, MappingGraph
                                            │
                                            ▼
                    App (SwiftUI): design system, features, SwiftData user data
```

- **Framework content is static.** It ships in the bundle and is read through FrameworkKit value types.
  Nothing about a framework is hard-coded in Swift. Adding a framework means adding a
  `*.framework.json` file (plus an optional `*.mapping.json`). `FrameworkStore` discovers it even
  when `index.json` does not list it.
- **User data is separate** (Phase 2). Assessments and responses are stored with SwiftData and keyed
  by `(frameworkID, requirementID)` strings. Regenerating content never requires migrating user data,
  and turning off a framework only hides its answers; nothing is deleted.
- **Mappings come only from NIST.** `MappingGraph` builds forward and reverse lookups from the
  mapping files and never chains or infers links.

## FrameworkKit

| Type | Responsibility |
|---|---|
| `FrameworkDocument`, `Requirement`, `TextItem`, `Parameter` | Codable mirror of `schema/framework.schema.json`. Unknown keys are ignored; a newer `schemaVersion` is rejected with a clear error. |
| `FrameworkStore` (actor) | Lazy loading and caching of the index, frameworks, search indexes, and the mapping graph, off the main thread. |
| `Framework` | A loaded document plus lookup indexes: requirement by ID, children by parent, group ancestry, and parameter scope per control family. |
| `ScopeSelection` | SP 800-53B baseline selection (base and additive baselines) plus manual additions. |
| `SearchIndex` | Inverted index with prefix matching and identifier-aware matching (`ac-02(01)` finds `AC-2(1)`). |
| `ParameterText` | Renders `{{param:ID}}` tokens with organization values or placeholders. |
| `ContentValidator` | The same structural rules as the Python validator, so any content file can be checked in the app. |
| `DesignTokens` (separate library) | Palette, spacing, and radius values, plus WCAG contrast math, tested without UIKit. |

## Performance notes

- `index.json` (about 12 KB) is all that loads at launch.
- SP 800-53 (about 2.5 MB of JSON) is decoded once, on the store actor, the first time it is opened.
- The search index is built once per framework in the background. Queries use binary search over
  sorted tokens.

## Security and privacy

See the plan. Data Protection (`NSFileProtectionComplete`) is set through the app entitlement. The app
makes no network calls and includes no third-party SDKs.
