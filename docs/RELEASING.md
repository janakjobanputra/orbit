# Releasing Orbit

Two release paths, both from `scripts/release.sh`:

- `make dmg` builds `dist/Orbit-v<version>.dmg`, signed with Developer ID and notarized by Apple, for people to download from GitHub Releases or the website.
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

## Releasing a version

1. Bump `MARKETING_VERSION` in `project.yml` and commit.
2. Run `make test`.
3. Run `make dmg`. It archives, exports, builds the disk image, notarizes (a few minutes), staples and checks it with Gatekeeper.
4. Create a GitHub release and attach `dist/Orbit-v<version>.dmg` and `dist/Orbit.dmg`. The website's Download buttons and the README go to `try-orbit.app/download`, which redirects to the newest release's `Orbit-v<version>.dmg` (see `site-worker.js`). `Orbit.dmg` is for `releases/latest/download/Orbit.dmg` links and for Orbit 1.1's in-app update check.
5. Run `make cask`, then commit and push the tap repo. If `MACOSX_DEPLOYMENT_TARGET` in `project.yml` changed, update the cask's `depends_on macos:` to match (`:sequoia` for 15, `:tahoe` for 26). `brew upgrade` picks up the new version from there.
6. Run `make testflight`. After processing (usually 10–30 minutes), add the build to a tester group in **TestFlight**. External testers need a one-time beta review. The export-compliance question is pre-answered in `Info.plist` (`ITSAppUsesNonExemptEncryption` is false).
