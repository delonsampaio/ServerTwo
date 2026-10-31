# App Store Connect setup for the Server Two Pro purchase

> **Check every menu name below.** This guide was written from memory, without
> access to App Store Connect, so button, menu and screen names may differ from
> what you see. Treat the steps as the intent and verify them against the
> current App Store Connect and Xcode documentation.

The app code is finished: it sells one non-consumable in-app purchase with the
product ID `com.delonsampaio.ServerTwo.pro`. Nothing sells until you create
that product in App Store Connect. These steps need your Apple Developer
account, so they have to be done by the owner.

## 1. Business agreements (once per account)

1. App Store Connect, **Business** (older UI: Agreements, Tax, and Banking).
2. Accept the **Paid Apps Agreement**.
3. Complete the **tax forms** and add a **bank account**. Until the status is
   Active, products can be created but real and sandbox purchases may not work.

## 2. Create the in-app purchase

1. App Store Connect, **Apps**, Server Two, **Monetization**, **In-App Purchases**, **+**.
2. Type: **Non-Consumable**.
3. **Reference Name:** `Server Two Pro` (internal only).
4. **Product ID:** `com.delonsampaio.ServerTwo.pro`. It must match exactly and
   cannot be changed or reused later.
5. **Price:** choose the price point that shows **$1.99** (Price Schedule, then
   Add Pricing). Other storefronts get an equivalent price automatically; the
   app shows whatever the App Store returns.
6. **Family Sharing:** tick **Turn on Family Sharing**. As far as I know this
   **cannot be turned off once enabled**, so decide now (verify the exact rule
   in App Store Connect). The app's copy already
   promises Family Sharing, and its entitlement logic handles shared and
   revoked copies.
7. **App Store Localization:** add at least English (U.S.):
   - Display Name: `Server Two Pro`
   - Description: `Unlimited matches with a one-time purchase. No subscription.`
8. **Review Information:** upload a **screenshot of the paywall** (open Settings,
   tap Unlock Server Two Pro, and take a screenshot of the sheet; any current
   iPhone size) and add a note such as: "Free users can play one full match.
   Starting another one shows this paywall."
9. Save. The status becomes **Ready to Submit**.

## 3. Attach it to the app version for review

The first in-app purchase must be reviewed together with an app version.

1. Open the app version you are submitting (App Store, iOS App, version).
2. In **In-App Purchases and Subscriptions**, click **+** (or **Select**) and
   add `Server Two Pro`.
3. Submit the version for review together with the in-app purchase. Later
   products and price changes do not need a new binary.

## 4. Create a Sandbox tester

1. App Store Connect, **Users and Access**, **Sandbox**, **Test Accounts**, **+**.
2. Use an email address that is not an existing Apple Account (a plus-address
   such as `you+sandbox1@gmail.com` works). Pick the storefront (region) to test.
3. Create more than one tester if you want to test Family Sharing behaviour
   (sandbox Family Sharing is limited; the Xcode configuration file is the
   better tool for that).

## 5. Test on a device

A new product can take **hours** to show up for sandbox purchases after it is
created. If the paywall shows "Couldn't load the price" at first, wait and retry.

**Builds run from Xcode (development builds):**

1. On the iPhone: **Settings, App Store, Sandbox Account** (the entry appears
   once the device has run a development build that used StoreKit) and sign in
   with the Sandbox tester. Do **not** sign in with it under the normal Apple
   Account.
2. In the app: finish the one free match, start another (or tap Settings, Unlock
   Server Two Pro), and buy. The purchase sheet says **[Environment: Sandbox]**.
   No money is charged.
3. Delete and reinstall the app, then tap **Restore Purchases** to check restore.
4. Manage sandbox purchases in **Settings, App Store, Sandbox Account, Manage**
   and in App Store Connect under the tester's account.

**TestFlight builds:** these use the sandbox automatically. No Sandbox Account
sign-in is needed; purchases are free and marked as test purchases.

## 6. Testing without App Store Connect (Xcode)

`ServerTwoTests/Products.storekit` is a local StoreKit configuration with the
same product. The unit tests use it automatically (`SKTestSession`). To run the
app itself against it: in Xcode, Product, Scheme, Edit Scheme, Run, Options,
**StoreKit Configuration**, pick `Products.storekit`. (The shared `ServerTwo`
scheme already points at it for the Run action; the path is stored relative to
the scheme file.)

While the app runs against that file, Xcode's **Debug, StoreKit, Manage
Transactions** window (Transaction Manager) lets you:

- see every transaction, **Refund** a purchase (the app should lock again),
  delete transactions, and reset the purchase state;
- **Approve / Decline** Ask to Buy requests (the Enable Ask to Buy switch is
  somewhere in the Transaction Manager window or the Xcode Editor / Debug menu;
  I am not sure where in your Xcode version);
- simulate errors, such as a failed product load or a failed purchase.

## 7. After release

- Refunds are handled by Apple (Report a Problem). The app re-locks the next
  time it reads its entitlements (at launch and whenever a transaction update
  arrives). A match in progress is never interrupted.
- App Store Connect, **Analytics** and **Sales and Trends** show purchases.

## 8. Release note: the Live Activity extension

The app embeds a Live Activity extension (`ServerTwoLiveActivity`) with its own
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Bump BOTH targets together
(app and extension) for every release, or App Store validation fails on the
mismatch. Its bundle id, `com.delonsampaio.ServerTwo.LiveActivity`, needs its
own App ID and provisioning profile; Automatic signing creates them on the
first signed build or archive.

## 9. TestFlight and Xcode Cloud

> **Menu names are from memory.** Xcode and App Store Connect rename and move
> things often, so the names below may differ from what you see. Follow the
> intent and check Apple's current documentation.

The repo is set up so that every push to `main` can produce a TestFlight build
through Xcode Cloud. What is already done in the project: placeholder app icons
(replace `ServerTwo/Assets.xcassets/AppIcon.appiconset/AppIcon.png` and the Watch
equivalent with your own 1024x1024 PNG, no transparency; `scripts/make_app_icon.py`
generated the placeholders), the Home Screen name `Server Two`, the export
compliance answer in the Info.plist, privacy manifests, shared schemes
in `ServerTwo.xcodeproj/xcshareddata`, and the privacy and support pages in
`docs/site/`.

### 9.1 Before you start

1. Open `docs/site/privacy.html` and `docs/site/support.html` and replace both
   occurrences of `[CONTACT EMAIL]` in each with your real contact address.
2. Host the pages. A simple option is GitHub Pages: repository **Settings**,
   **Pages**, source **Deploy from a branch**, branch `main`, folder `/docs`.
   The pages would then be at
   `https://<your-github-user>.github.io/<repo-name>/site/privacy.html` and
   `.../site/support.html`.
   **Note:** this publishes everything under `docs/`, including the design
   specs and plans in `docs/superpowers/` and this guide. If you do not want
   that, move the two pages to their own folder (or a separate repository) and
   publish only that.

### 9.2 Create the app record

1. App Store Connect, **Apps**, **+**, **New App**.
2. Platforms: **iOS**. (The Watch app ships inside the iOS app.)
3. **Name:** `Server Two: Pickleball Tracker` (or a variation if the name is
   taken; it can differ from the Home Screen name `Server Two`). The App Store
   name limit is 30 characters, and this one is 30 or fewer, but check.
4. **Primary language:** English (U.S.) or whichever you prefer.
5. **Bundle ID:** `com.delonsampaio.ServerTwo`. It appears in the list once an
   Xcode build with automatic signing has registered it; if it is missing,
   archive once from Xcode, or register it under **Certificates, Identifiers &
   Profiles**. The Watch app (`com.delonsampaio.ServerTwo.watchkitapp`) and the
   Live Activity (`com.delonsampaio.ServerTwo.LiveActivity`) get their own IDs
   automatically.
6. **SKU:** any unique string, for example `servertwo-ios`.
7. Create the Pro in-app purchase if you have not (section 2 above), with product ID
   `com.delonsampaio.ServerTwo.pro`.

### 9.3 App information fields

- **Privacy Policy URL:** the hosted `privacy.html`.
- **Support URL:** the hosted `support.html`. (A marketing URL is optional.)
- **App Privacy** (the privacy "nutrition label"): answer that you **do not
  collect data from this app**. Reasoning: matches and players stay on the device
  and in the user's own private iCloud, there are no analytics or third-party
  SDKs, and Health data stays on the Watch and in Apple Health and is never sent
  to you. Tracking: **No**.
- **Export compliance:** already answered by `ITSAppUsesNonExemptEncryption = NO`
  in the Info.plist of the iOS and Watch targets (only standard HTTPS and
  CloudKit). App Store Connect should not ask for it on each build.
- Age rating and the rest of the app information are needed for App Store
  review, but not for internal TestFlight testing.

### 9.4 Create the Xcode Cloud workflow

1. Open `ServerTwo.xcodeproj` in Xcode and sign in with the Apple Account
   that has the developer team (`4CD86DZ6WP`).
2. **Product**, **Xcode Cloud**, **Create Workflow...** (or the Cloud tab in
   the Report navigator).
3. Select the **ServerTwo** app/product when asked, then grant Xcode Cloud
   access to the GitHub repository when the browser asks (install the Xcode
   Cloud GitHub app for that repository).
4. Workflow settings:
   - **Start condition:** **Branch Changes**, branch `main`.
   - **Environment:** latest release Xcode (and the matching macOS).
   - **Action:** **Archive**, platform **iOS**, scheme `ServerTwo`, distribution
     preparation **TestFlight (Internal Testing Only)**. The Watch app and Live
     Activity are built as part of the iOS scheme.
   - **Post-action:** **TestFlight Internal Testing**, with a tester group that
     contains you. (Create the group in App Store Connect, **TestFlight**,
     **Internal Testing**, **+**, and add your own Apple Account as a tester.)
5. Save and start the first build, or push to `main`.

Do not add a Test action at first. The UI tests need simulators and are slow.
Add one later if you want it.

### 9.5 Install the build

1. When the build finishes and processes (a few minutes after it succeeds in
   Xcode Cloud), install the **TestFlight** app on the iPhone and sign in with
   the same Apple Account. The build appears under Server Two; tap **Install**.
2. The Watch app installs from the iPhone: open the **Watch** app on the iPhone,
   scroll to **Available Apps** (or the Server Two row), and tap **Install**.
   With "Automatic App Install" turned on it may arrive by itself.
3. Internal testers (up to 100 people on your team) do not need Apple's beta
   review. Builds expire after 90 days.

### 9.6 Caveats

- **Build numbers.** Xcode Cloud manages the build number (`CFBundleVersion`,
  from `CURRENT_PROJECT_VERSION`, which is 1 in the project) for the archives it
  uploads. If an upload is refused because a build with that number already
  exists for the version, the fix is a `ci_scripts/ci_post_clone.sh` or
  `ci_scripts/ci_pre_xcodebuild.sh` script that sets the build number from the
  `CI_BUILD_NUMBER` environment variable, for example with
  `agvtool new-version -all "$CI_BUILD_NUMBER"` (run in the repository root;
  mark the script executable). The app, the Watch app and the Live Activity must
  all end up with the same build number, which `agvtool` with `-all` does for
  the whole project. I did not add such a script, because I could not confirm
  that it is needed; check the first build.
- **Free compute.** From memory, the Apple Developer Program includes about
  25 compute hours per month for Xcode Cloud. Confirm the current allowance and
  pricing in App Store Connect or Apple's Xcode Cloud page before relying on it.
  A push to `main` starts a build, so batch commits if you push often.
- **Signing.** Xcode Cloud manages signing in the cloud. The Live Activity
  extension and the Watch app need their App IDs, which Xcode creates the
  first time; if the first cloud build fails on signing or capabilities
  (iCloud, Push, HealthKit), read the error: it usually means an App ID needs
  that capability enabled under Certificates, Identifiers & Profiles.
- **Placeholder icon.** Replace the placeholder icons before any public release.
