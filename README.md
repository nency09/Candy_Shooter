# Candy Shooter

A Flutter bubble-shooter puzzle game with optional Supabase account, cloud-save
and public leaderboard features.

## Verify locally

```powershell
flutter analyze
flutter test -r expanded
flutter run
```

## Android release setup

Release builds require a private upload keystore; the project will no longer
fall back to the insecure debug signing certificate.

1. Generate and safely back up a keystore. Do not commit it.

   ```powershell
   keytool -genkeypair -v -keystore android\upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Copy `android/key.properties.example` to `android/key.properties` and
   replace every placeholder. `storeFile` is relative to `android/`.
3. Build the signed artifact.

   ```powershell
   flutter build appbundle --release
   ```

The app has the Android Internet permission in its main manifest, so Supabase
network features are available in release as well as debug builds.

## Supabase production setup

Before applying database changes, create a backup in Supabase Dashboard. Install
the Supabase CLI, sign in, and link it to the production project. Then review
and apply the migrations in chronological order, including:

- `20260827232000_harden_leaderboard_submission.sql`
- `20260901090000_lock_down_leaderboard_tables.sql`

The final migration removes all client read/write access to the private
leaderboard source tables. The app reads only the safe public leaderboard views
and writes results through `submit_leaderboard_result`.

In Supabase Dashboard > Authentication > URL Configuration, set the production
Site URL and add this redirect URL exactly:

```
com.candyshooter.candyshooter://login-callback
```

Also configure Google as an Auth provider and add the Supabase Auth callback URL
to the Google Cloud OAuth client. Confirm that the Dashboard email-confirmation
setting matches the app's sign-up message.

## Security note

The database now blocks direct table-level leaderboard forgery. A mobile client
can still be modified by a determined attacker, so a fully cheat-proof ranking
system requires server-authoritative gameplay or server-side validation of each
game result. Do not treat client-owned cloud progress as proof of a score.

## Remaining product decisions

- Add a licensed music asset and playback implementation, or remove the Music
  toggle from Settings.
- Configure desktop deep links before enabling Google sign-in or password reset
  for Windows, macOS, or Linux releases.
