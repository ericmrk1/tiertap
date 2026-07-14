# App Store Connect — Apple Review checklist (TierTap)

Use this for App Store Connect metadata and sandbox verification after Guideline **3.1.2(c)**, **5.1.1(v)**, and **2.1(b)** feedback.

## 1. Terms of Use (EULA) — metadata (3.1.2)

TierTap uses **Apple’s standard EULA**.

1. Open **App Store Connect → TierTap → App Information** (or the version’s **App Store** tab).
2. In the **App Description**, include a functional link, for example at the end:

```text
Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://travelzork.com/privacy-policy/
```

3. Confirm **Privacy Policy URL** is set to: `https://travelzork.com/privacy-policy/`

### In-app (already in the binary)

- Paywall: **Terms of Use (EULA)** and **Privacy Policy** links (near plans and in Legal).
- Settings → About: Privacy + Terms of Use (EULA).

## 2. Account deletion (5.1.1)

In the app:

1. **Settings → TierTap Account** (or Community **Account** sheet).
2. Sign in if needed.
3. Tap **Delete Account** → confirm.

### Backend

Apply migration `CTT/supabase/migrations/20260714120000_delete_own_account.sql` on the production Supabase project (fallback RPC if GoTrue `DELETE /auth/v1/user` fails).

```bash
# Example with Supabase CLI (adjust project ref as needed)
supabase db push
```

### Review Notes (App Review Information)

Paste something like:

```text
Account deletion: Settings → TierTap Account → Delete Account → confirm.
We also expose Delete Account on the Community Account sheet.
Screen recording: [attach] sign-in → Delete Account → confirmation → signed out.
```

## 3. In-App Purchases / paywall (2.1)

Reviewers saw “Subscription plans aren’t available…” when StoreKit returned no subscription products.

### Product IDs (must match exactly)

| Product | ID | Type |
|--------|----|------|
| Monthly | `com.app.subs.tiertap.monthly` | Auto-renewable |
| 3 Months | `com.app.subs.tiertap.quarterly` | Auto-renewable |
| Yearly | `com.app.subs.tiertap.yearly` | Auto-renewable |
| Token pack | `Credits` | Consumable |

Subscription group: `com.app.subs.tiertap`

### App Store Connect checklist

1. **Business → Paid Apps Agreement** is Active (Account Holder).
2. Each subscription has:
   - Display name + description (localized)
   - Pricing for required territories
   - Review screenshot / notes if requested
   - **Cleared for Sale** / Ready to Submit with the app version
3. Sandbox test: sign in with a Sandbox Apple ID on a device, open TierTap Pro paywall, pull to refresh — plans must show live prices and **Subscribe** (not Unavailable).
4. Local Xcode testing uses `TierTapStoreKitConfig.storekit` (scheme StoreKit Configuration).

### Review Notes for IAP

```text
IAP sandbox: products com.app.subs.tiertap.monthly / .quarterly / .yearly and consumable Credits.
Paywall: Settings → Upgrade/Manage TierTap Pro (or any gated Pro entry).
Pull down on the paywall to refresh the catalog.
Paid Apps Agreement: Active.
```

## 4. After fixing — reply to App Review

In App Store Connect, reply with:

1. Confirmation that App Description includes the EULA link and Privacy Policy field is set.
2. Screen recording of account deletion on a physical device.
3. Screen recording of the paywall with subscription plans loading (sandbox), plus Terms/Privacy links visible.
