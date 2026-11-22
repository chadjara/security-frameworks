# Content sources and licensing

All framework content comes from NIST publications. NIST works are generally not subject to
copyright in the United States (17 U.S.C. § 105) and NIST permits redistribution. Exact
URLs, commit, file hashes, and retrieval dates are recorded in
[`data/sources/SOURCES.json`](../data/sources/SOURCES.json) and copied into each generated file's
`source` block.

| Framework | Source | Version |
|---|---|---|
| NIST Cybersecurity Framework 2.0 | `usnistgov/oscal-content` → `nist.gov/CSF/v2.0/json/NIST_CSF_v2.0_catalog.json` | CSF 2.0 (OSCAL catalog 1.2.1) |
| NIST SP 800-53 Rev. 5 | `usnistgov/oscal-content` → `nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_catalog.json` | Release 5.2.0 |
| NIST SP 800-53B baselines | `…/NIST_SP-800-53_rev5_{LOW,MODERATE,HIGH,PRIVACY}-baseline_profile.json` | Release 5.2.0 |
| NIST SP 800-171 Rev. 3 | `usnistgov/oscal-content` → `nist.gov/SP800-171/rev3/json/NIST_SP800-171_rev3_catalog.json` | Rev. 3 (OSCAL catalog 1.1.0) |
| CSF 2.0 informative references | NIST CPRT, CSF 2.0 Reference Tool export | Retrieved date in `SOURCES.json` |

## Mappings

Only NIST-published mappings are used:

- **SP 800-171 Rev. 3 → SP 800-53 Rev. 5.** The source controls each SP 800-171 requirement cites
  (reference links in the SP 800-171 Rev. 3 OSCAL catalog). NIST cites SP 800-53 Release 5.1.1.
  Every cited identifier exists unchanged in Release 5.2.0, and the converter enforces this.
- **CSF 2.0 → SP 800-53 Rev. 5 (Release 5.2.0)** and **CSF 2.0 → SP 800-171 Rev. 3.** NIST's CSF 2.0
  informative references, from the CPRT CSF 2.0 Reference Tool.

The CPRT export also lists informative references to third-party standards (ISO/IEC, PCI DSS,
CIS, CSA CCM, and others). `fetch_sources.py` discards them during download. Only the NIST
SP 800-53 Rev. 5.2.0 and SP 800-171 Rev. 3 references are committed, and the original
workbook's hash is recorded.

Published references that cannot be represented are listed under `unresolved` in each mapping
file and are not used. These are references to a withdrawn control, or to a whole SP 800-53
family rather than a single control.

## What is excluded

- Copyrighted third-party standards: no text, clause numbers, or identifiers from ISO, CIS
  Controls, PCI DSS, COBIT, CSA CCM, or similar.
- Bibliography entries in SP 800-53 and SP 800-171 that are not NIST publications. The app
  keeps NIST SP, FIPS, IR, and CSWP references only.
- SP 800-53A assessment methods and objects. Assessment objectives are kept.
- Withdrawn controls and requirements, which are kept only as lookup stubs.

## Editorial content

The plain-language layer (summaries, notices, questions, "why it matters", "what done looks
like", next steps) is written for this app in `data/editorial/`. It is not NIST text and is
marked `reviewed: false` until a qualified reviewer approves it.

## Independence

This app is independent and is not affiliated with or endorsed by NIST. It is a
self-assessment aid, not a certification or compliance attestation.
