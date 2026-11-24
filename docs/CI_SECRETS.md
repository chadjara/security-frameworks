# Shipping builds to TestFlight

GitHub Actions builds, signs, and uploads the app. No Mac or Xcode is needed on your side. You do
five one-time setup steps in your Apple and GitHub accounts. After that, each build is one click.

| Value | Secret name | Where it comes from |
|---|---|---|
| App Store Connect API key ID | `ASC_KEY_ID` | Step 3 |
| App Store Connect issuer ID | `ASC_ISSUER_ID` | Step 3 |
| The API key file's contents | `ASC_PRIVATE_KEY` | Step 3 |
| Your Apple Developer Team ID | `APPLE_TEAM_ID` | Step 4 |

## 1. Register the bundle ID

1. Go to [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles** → **Identifiers** → **+**.
2. Choose **App IDs** → **App** → Continue.
3. **Description:** anything, for example `Security Frameworks`.
4. **Bundle ID:** Explicit, `com.cjaratech.securityframework`.
5. Under **Capabilities**, check **Data Protection** and choose **Complete Protection**. The app keeps
   assessment data encrypted whenever the device is locked.
6. Continue → Register.

## 2. Create the app record in App Store Connect

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**.
2. **Platforms:** iOS. **Name:** the name shown on the App Store. It must be unique across the store,
   so "FrameworkApp" may be taken; any placeholder works and you can change it before release.
   **Primary language:** English (U.S.). **Bundle ID:** pick `com.cjaratech.securityframework`.
   **SKU:** any internal code, for example `securityframeworks`. **User access:** Full Access.
3. Create.
4. Under **App Information**, set the **Privacy Policy URL** to
   `https://cjaratech.com/securityframeworks/privacypolicy`. [APP_STORE.md](APP_STORE.md) lists the
   other App Store Connect fields, including the App Privacy answers.

## 3. Create an App Store Connect API key

1. In App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → **+**.
2. **Name:** `GitHub Actions`. **Access:** **Admin**.
   Admin is needed so the build can create and use Apple-managed (cloud) signing certificates for you.
   There are no certificate or provisioning-profile files to manage.
3. Generate, then **Download API Key**. You can download the `.p8` file only once; keep it somewhere safe.
4. Note the **Key ID** (in the keys table) and the **Issuer ID** (shown above the table).

## 4. Find your Team ID

[developer.apple.com/account](https://developer.apple.com/account) → **Membership details** → **Team ID**
(10 characters, for example `A1B2C3D4E5`).

## 5. Add the secrets to GitHub

In the repository on GitHub: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.
Create each of these:

- `ASC_KEY_ID`: the Key ID from step 3.
- `ASC_ISSUER_ID`: the Issuer ID from step 3.
- `ASC_PRIVATE_KEY`: open the downloaded `AuthKey_XXXXXXXXXX.p8` in a text editor and paste the
  whole contents, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines.
  A base64-encoded copy of the file also works.
- `APPLE_TEAM_ID`: the Team ID from step 4.

GitHub encrypts secrets. They never appear in logs, and they are not available to pull requests
from forks.

## Upload a build

- **From GitHub:** **Actions** → **TestFlight** → **Run workflow**.
- **Or with a tag:** push a tag that starts with `v`, for example `v0.1.0-beta.1`.

The workflow archives a Release build, signs it, and uploads it. Build numbers are assigned
automatically and always increase. The run's summary shows the version and build number.

## Install it with TestFlight

1. After the upload, Apple processes the build. This usually takes 10–30 minutes, and you get an email when it is ready.
2. App Store Connect → your app → **TestFlight** → **Internal Testing** → **+** to create a group, add
   yourself (and anyone on your team), and add the build.
3. Install the **TestFlight** app on your iPhone or iPad and accept the invitation.

The export compliance question is answered automatically: the app declares that it uses only the
encryption built into iOS (`ITSAppUsesNonExemptEncryption = NO`). Recheck this before a public release.

## If a run fails

| Message | Fix |
|---|---|
| `Missing repository secrets` | Add the secrets listed above (step 5). |
| `No Accounts` / `Cloud signing permission error` | The API key must have the **Admin** role (step 3). |
| `No profiles for 'com.cjaratech.securityframework' were found` | Register the bundle ID exactly as written (step 1). |
| `No suitable application records were found` | Create the app record (step 2) with the same bundle ID. |
| `The bundle version must be higher than the previously uploaded version` | Run the workflow again; it uses a new build number. |
| `exportArchive Error Downloading App Information` | The archive was signed but the upload could not find the app. Check that the app exists in App Store Connect with bundle ID `com.cjaratech.securityframework` (step 2), and that no agreement is waiting in App Store Connect → Business. The run's `distribution-logs` artifact has Apple's details. |
| `Your account already has an Apple Development signing certificate … private key is not installed` | The workflow signs with distribution certificates only, so this should not appear. If an older run created an "Apple Development" certificate, you can revoke it in Certificates, Identifiers & Profiles → Certificates. |
| `Missing entitlement com.apple.developer.default-data-protection` | Enable **Data Protection → Complete Protection** on the App ID (step 1). |

### GitHub has no Mac runner available

If a run ends with "The job was not acquired by Runner of type hosted", GitHub had no free macOS
runner of that type. Wait and run it again. To use a different runner image instead, add a repository
**variable** (Settings → Secrets and variables → Actions → **Variables** tab) named `MACOS_RUNNER` with
a value such as `macos-26` or `macos-15`. Both workflows use it in place of the default `macos-15-intel` and pick the
newest Xcode installed on the image.

To stop using the key at any time, revoke it in App Store Connect → Users and Access → Integrations.
