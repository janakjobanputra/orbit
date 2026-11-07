# Releasing Orbit

Two release paths, both from `scripts/release.sh`:

- `make dmg` builds `dist/Orbit-v<version>.dmg`, signed with Developer ID and notarized by Apple, for people to download from GitHub Releases or the website.
- `make appcast` writes `dist/appcast.xml`, the feed Orbit's built-in updater (Sparkle) reads, signed for that DMG.
- `make testflight` uploads a build to App Store Connect, where it shows up in TestFlight.
- `make cask` points the Homebrew cask (`Casks/orbit-calendar.rb` in [janakjobanputra/homebrew-tap](https://github.com/janakjobanputra/homebrew-tap)) at the new DMG. It expects that repo checked out next to this one, or set `TAP_DIR`.

The version comes from `MARKETING_VERSION` in `project.yml`. Each build gets a timestamp build number such as `202611020851`, so every upload is higher than the last.

## One-time setup

These steps need the Apple Developer account holder and can't be scripted.

### 1. Certificates

In Xcode, open **Settings › Accounts**, select your team, click **Manage Certificates…**, then use **+** to add:

- **Developer ID Application**, for the DMG. Only the account holder can create it.
- **Apple Distribution**, for TestFlight and the App Store.

Check they're installed:

```bash
security find-identity -v -p codesigning
```

### 2. Notarization credentials

Create an app-specific password at [account.apple.com](https://account.apple.com) › Sign-In and Security › App-Specific Passwords, then save it to your keychain under the profile name the script uses:

```bash
xcrun notarytool store-credentials orbit-notary --apple-id YOUR_APPLE_ID --team-id Y82QXWVLD9
```

It prompts for the password, so the password never lands in your shell history.

### 3. App Store Connect app record

Needed once before the first TestFlight upload:

1. In [App Store Connect](https://appstoreconnect.apple.com), go to **Apps › + › New App**.
2. Platform **macOS**, name **Orbit**, bundle ID **com.janakjobanputra.Orbit**, any SKU (for example `orbit`).
3. If the bundle ID isn't in the list, register it under **Certificates, Identifiers & Profiles › Identifiers** first, or run `make testflight` once and let Xcode register it.

Xcode must be signed in to the same account (**Settings › Accounts**), because the upload uses that session.

### 4. The update signing key

Orbit only installs updates signed with this key. The public half is `SUPublicEDKey` in `Orbit/Info.plist`, and the private half is in the login keychain of the Mac that made it (account `orbit`), where `make appcast` finds it. **Lose it and installed copies can't update to anything you sign afterwards**, so keep a backup somewhere safe, such as a password manager:

```bash
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account orbit -x orbit-sparkle-key.txt
```

Delete the exported file once it's stored. On a new Mac, bring it back with `generate_keys --account orbit -f orbit-sparkle-key.txt`.

### 5. The reports database

Crash reports and opt-in usage stats go to `/api/crash` and `/api/usage` on the try-orbit.app Worker, which stores them in a Cloudflare D1 database. Until the database is attached, the Worker turns reports away and nothing else changes. Create it once:

```bash
npx wrangler login
npx wrangler d1 create orbit-reports
npx wrangler d1 execute orbit-reports --remote --file migrations/0001_reports.sql
```

Then add the `d1_databases` block it prints to `wrangler.jsonc`, with the binding named `DB`, and push.

`make metrics` prints the numbers, using your own Cloudflare login. Crash stacks are binary offsets: keep each release's `dist/Orbit.xcarchive`, whose dSYM turns them into function names.

## Releasing a version

1. Bump `MARKETING_VERSION` in `project.yml` and commit.
2. Run `make test`.
3. Run `make dmg`. It archives, exports, builds the disk image, notarizes (a few minutes), staples and checks it with Gatekeeper.
4. Write `dist/release-notes-<version>.md` with a `### What's new in <version>` heading, then run `make appcast`. Everything from that heading on is what the update window shows.
5. Create a GitHub release, marked Latest, and attach `dist/Orbit-v<version>.dmg`, `dist/Orbit.dmg` and `dist/appcast.xml`. Installed copies read `releases/latest/download/appcast.xml`, so the update goes out the moment the release is published. The website's Download buttons and the README go to `try-orbit.app/download`, which redirects to the newest release's `Orbit-v<version>.dmg` (see `site-worker.js`). `Orbit.dmg` is for `releases/latest/download/Orbit.dmg` links and for the update checker in Orbit 1.1 to 1.1.4, which predates Sparkle.
6. Run `make cask`, then commit and push the tap repo. If `MACOSX_DEPLOYMENT_TARGET` in `project.yml` changed, update the cask's `depends_on macos:` to match (`:sequoia` for 15, `:tahoe` for 26). The cask says `auto_updates true`, so Homebrew leaves updating to Orbit itself. `brew install` still gets the new version from there.
7. Run `make testflight`. **Not yet working with Sparkle:** App Store builds can't include it, and its sandbox exception would be rejected, so this needs a separate App Store configuration without Sparkle first. After processing (usually 10–30 minutes), add the build to a tester group in **TestFlight**. External testers need a one-time beta review. The export-compliance question is pre-answered in `Info.plist` (`ITSAppUsesNonExemptEncryption` is false).
