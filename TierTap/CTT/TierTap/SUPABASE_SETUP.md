# Supabase auth (Community tab)

The Community tab includes optional Supabase sign-in (magic link). To enable it:

## 1. Add Supabase credentials (kept out of git)

Keys are read from **SupabaseKeys.plist**, which is **gitignored** so they are never committed.

1. Copy **SupabaseKeys.example.plist** to **SupabaseKeys.plist** (same folder).
2. In **SupabaseKeys.plist**, set:
   - **SUPABASE_URL** – Your project URL (e.g. `https://xxxx.supabase.co`)
   - **SUPABASE_ANON_KEY** – Your project’s anon/publishable key

You can copy these from the [Supabase Dashboard](https://supabase.com/dashboard) → your project → **Settings** → **API** (Project URL and anon key). New clones of the repo should create **SupabaseKeys.plist** from the example and add their own keys.

## 2. Redirect URL for magic links

The app uses the URL scheme `com.app.tiertap://login-callback` for magic link sign-in.

In the Supabase Dashboard → **Authentication** → **URL Configuration**, add this to **Redirect URLs**:

- `com.app.tiertap://login-callback`

The app’s **Info.plist** already declares the `com.app.tiertap` URL scheme so the system opens the app when the user taps the magic link.

## 3. Swift package

The project is set up to use the [supabase-swift](https://github.com/supabase/supabase-swift) package. If the package didn’t resolve:

1. In Xcode: **File** → **Add Package Dependencies...**
2. Enter: `https://github.com/supabase/supabase-swift`
3. Add the **Supabase** product to the **TierTap** target.

After building, the Community tab will show “Sign in with Supabase” below the “coming soon” text. If the keys are missing, it will show instructions to add them to Info.plist.

## 4. Sign in with Apple (optional)

1. **Enable Apple provider** in the Supabase Dashboard → **Authentication** → **Providers** → **Apple** (turn it on).
2. **Add your App ID** to the Apple provider's **Client IDs** list. Use your app's bundle ID (e.g. `com.app.tiertap`). Native Sign in with Apple does not require OAuth (Services ID, signing key, etc.); just add the bundle ID.
3. The TierTap target already has the **Sign in with Apple** entitlement. In the Apple Developer portal, ensure your App ID has the Sign in with Apple capability.

## 5. Sign in with Google (optional)

Google sign-in uses the OAuth flow (in-app browser). The same redirect URL `com.app.tiertap://login-callback` is used.

1. **Google Cloud Console**: Create a project (or use an existing one). In **APIs & Services** → **Credentials**, create an **OAuth 2.0 Client ID**:
   - For the OAuth consent screen, set up the required scopes (e.g. `userinfo.email`, `userinfo.profile`, `openid`).
   - Create a **Web application** client and note the Client ID and Client Secret.
   - Under **Authorized redirect URIs**, add your Supabase auth callback, e.g. `https://<your-project-ref>.supabase.co/auth/v1/callback` (from the Supabase Dashboard → Authentication → URL Configuration).
   - Optionally create an **iOS** client with your app’s bundle ID (e.g. `com.app.tiertap`) and add that Client ID to Supabase as well.

2. **Supabase Dashboard**: **Authentication** → **Providers** → **Google**:
   - Enable the provider.
   - Paste the **Client ID** and **Client Secret** from the Web application client.
   - Under **Client IDs**, you can add the iOS client ID if you created one (comma-separated with the web client ID).

3. Ensure `com.app.tiertap://login-callback` is in your project’s **Redirect URLs** (same as step 2 in this doc).
