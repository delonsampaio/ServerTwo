# App Store Connect setup for the Server Two Pro purchase

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
5. **Price:** choose the tier closest to **$1.99 USD** (Price Schedule, then
   Add Pricing). Other storefronts get an equivalent price automatically; the
   app shows whatever the App Store returns.
6. **Family Sharing:** tick **Turn on Family Sharing**. **This cannot be turned
   off once the product is live**, so decide now. The app's copy already
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

1. Install a build signed with your team (Run from Xcode, or TestFlight).
2. On the iPhone: **Settings, App Store, Sandbox Account** (scroll to the bottom
   of the App Store settings; it appears after a sandbox sign-in was triggered
   or on iOS builds with Developer Mode on) and sign in with the Sandbox tester.
   Do **not** sign in with it under the normal Apple Account.
3. In the app: finish the one free match, start another (or tap Settings,
   Unlock Server Two Pro), and buy. The purchase dialog says **[Environment:
   Sandbox]**. No money is charged.
4. Delete and reinstall the app, then tap **Restore Purchases** to check restore.
5. Manage or clear sandbox purchases in **Settings, App Store, Sandbox Account,
   Manage** (and in App Store Connect, Sandbox, Test Accounts, the tester's
   purchase history).

## 6. Testing without App Store Connect (Xcode)

`ServerTwoTests/Products.storekit` is a local StoreKit configuration with the
same product. The unit tests use it automatically (`SKTestSession`). To run the
app itself against it: in Xcode, Product, Scheme, Edit Scheme, Run, Options,
**StoreKit Configuration**, pick `Products.storekit`. (The project has no
shared scheme, so this is a local setting.)

While the app runs against that file, Xcode's **Debug, StoreKit, Manage
Transactions** window (Transaction Manager) lets you:

- see every transaction, **Refund** a purchase (the app should lock again),
  delete transactions, and reset the purchase state;
- **Approve / Decline** Ask to Buy requests (turn on Enable Ask to Buy in the
  same window's toolbar);
- simulate errors, such as a failed product load or a failed purchase.

## 7. After release

- Refunds are handled by Apple (Report a Problem). The app re-locks the next
  time it reads its entitlements (at launch and whenever a transaction update
  arrives). A match in progress is never interrupted.
- App Store Connect, **Analytics** and **Sales and Trends** show purchases.
