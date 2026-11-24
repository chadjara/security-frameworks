# App Store Connect settings

Values to enter in App Store Connect for this app. Shipping builds to TestFlight is covered in
[CI_SECRETS.md](CI_SECRETS.md).

## URLs

| Field | Where | Value |
|---|---|---|
| Privacy Policy URL | App Information → General | `https://cjaratech.com/securityframeworks/privacypolicy` |
| Support URL | Version page → App Information (each version) | `https://cjaratech.com/securityframeworks` |
| Marketing URL (optional) | Version page | `https://cjaratech.com/securityframeworks` |
| Privacy Policy URL for testers | TestFlight → Test Information | `https://cjaratech.com/securityframeworks/privacypolicy` |

The privacy policy text, written to match what the app does, is in [privacy-policy.md](privacy-policy.md).
Publish it at the privacy policy URL before inviting external testers or submitting for review. The
same URLs are linked inside the app from Settings and About (`App/Support/AppLinks.swift`).

## App Privacy ("nutrition label")

App Store Connect → **App Privacy** → **Get Started**:

- "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app.**
- Result: **Data Not Collected**.

This matches the app: no network access, no analytics or third-party SDKs, and all data stored on
the device. The app's `PrivacyInfo.xcprivacy` declares the same.

## TestFlight

- **Internal testing** (you and members of your App Store Connect team): available as soon as a build
  finishes processing. No review is needed.
- **External testing** (anyone with an email invite or a public link): fill in **Test Information**:
  beta app description, feedback email, and the privacy policy URL. The first external build goes
  through Beta App Review, which usually takes about a day.

## Suggested listing details

- **Category:** Business (primary), Productivity (secondary).
- **Age rating:** answer "None" to every content question; the result should be 4+.
- **Export compliance:** handled in the build (`ITSAppUsesNonExemptEncryption = NO`, meaning the app
  uses only encryption built into iOS). Recheck this before a public release.
- **App Review notes:** "All data stays on the device. No account or sign-in is needed. Create an
  assessment, turn on a framework, and answer requirements."

## Before a public release

- Choose the final app name. The display name is set in `project.yml` (`CFBundleDisplayName`).
- Have the plain-language content reviewed; every entry is marked `reviewed: false` until then.
- Make sure the About screen and the listing both state that the app is independent of NIST and is a
  self-assessment aid, not a certification.
