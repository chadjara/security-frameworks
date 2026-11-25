# App Store listing

The listing text lives in `metadata/` (fastlane `deliver` layout) and is uploaded by the
**App Store** workflow (`.github/workflows/appstore.yml`, Actions tab → App Store → Run workflow).

| Run with | What happens |
|---|---|
| defaults | Captures screenshots (6.9-inch iPhone, 13-inch iPad), uploads them and the text below. Nothing is submitted. |
| **submit** checked | Same, then submits the version for App Review with the newest build (or **build_number**). |

Automatic release is off: after Apple approves, the version waits in App Store Connect until you
press **Release This Version**.

## Files

| File | Limit | Notes |
|---|---|---|
| `en-US/name.txt` | 30 | Must not be used by another app. |
| `en-US/subtitle.txt` | 30 | |
| `en-US/keywords.txt` | 100 | Comma separated. Words already in the name are indexed anyway. |
| `en-US/promotional_text.txt` | 170 | Can change at any time without a new version. |
| `en-US/description.txt` | 4000 | |
| `copyright.txt`, `*_category.txt`, URLs | | |
| `review_information/` | | Notes for the reviewer. Phone and email come from the secrets `REVIEW_CONTACT_PHONE` and `REVIEW_CONTACT_EMAIL` if set; otherwise enter them in App Store Connect. |

## Steps that stay in App Store Connect

Apple's API key cannot do these; each takes a minute in the web interface.

1. **App Privacy** → Get Started → "No, we do not collect data from this app" (Data Not Collected).
2. **Pricing and Availability** → Free; choose countries.
3. **Age Rating** (App Information) → answer None / No to every question.
4. **App Review Information** → phone and email, unless the secrets above are set.
5. Publish the updated privacy policy (`docs/privacy-policy.md`, now using the name Security
   Frameworks) at the privacy policy URL.

## Before submitting

- Have the plain-language content reviewed (`data/editorial/`; entries are `reviewed: false`).
- Upload a TestFlight build of the version in `project.yml` and try it on a device.
