# Releasing Brow

How to make a build that other people can open without Gatekeeper's "cannot be opened" warning: signed with a
Developer ID, hardened, notarized by Apple and stapled. For your own Mac none of this is needed: `make run` is enough.

`make release` does the whole thing once the one-time setup below is done. Nothing here has been run end to end yet:
the setup needs an Apple Developer account, and the Mac this was written on only has an "Apple Development"
certificate, which is for running your own builds, not for sharing them.

## What is already in the repo

- Bundle id `dev.bosan.Brow` (`Support/Info.plist`). Changing it later makes macOS treat the app as a new one: the
  Calendar permission and the login item would be asked for again. Settle it before the first release.
- `Support/Brow.entitlements`: the Calendar entitlement. The hardened runtime, which notarization requires, only lets
  an app read Calendar with it. Nothing else is needed (no network, no sandbox, no scripting).
- `make hardened`: the same hardened signature with your everyday identity, to see that the app still works (Calendar
  included) before spending a notarization. Checked on 26 Nov 2026: it runs and shows events.
- `make release`: sign with the Developer ID, zip, submit to Apple and wait, staple the ticket, check it with
  `spctl`, and zip again so the zip carries the ticket. The result is `build/Brow-<version>.zip`.

## One-time setup

1. **Join the Apple Developer Program** (paid, yearly). A free Apple ID can sign for development only.
2. **Make a "Developer ID Application" certificate.** Xcode → Settings → Accounts → your team → Manage Certificates →
   + → Developer ID Application. Then `security find-identity -v -p codesigning` lists it as
   `Developer ID Application: Your Name (TEAMID)`.
3. **Store notarization credentials in the keychain.** Make an app-specific password at account.apple.com
   (Sign-In and Security → App-Specific Passwords), then run the command below and type the password when asked.
   Nothing is written to the repo.

   ```bash
   xcrun notarytool store-credentials "brow-notary" --apple-id "you@example.com" --team-id "TEAMID"
   ```

4. **Tell the Makefile who you are**, in `Makefile.local` (it is not committed):

   ```make
   SIGN_ID        := Apple Development: Your Name (TEAMID)
   DEVELOPER_ID   := Developer ID Application: Your Name (TEAMID)
   NOTARY_PROFILE := brow-notary
   ```

## Each release

1. Raise `CFBundleShortVersionString` and `CFBundleVersion` in `Support/Info.plist`.
2. `make test`, then `make hardened` and open `build/Brow.app` to look it over.
3. `make release`. It takes a few minutes while Apple scans the zip.
4. Before sharing, open the zip on another Mac (or a fresh user account) that has never run Brow: it should open with
   no warning other than the one-time "downloaded from the internet" prompt, and ask for Calendar access once.
5. Share `build/Brow-<version>.zip`, for example as a GitHub release.

## If something goes wrong

- **Notarization says "Invalid".** `xcrun notarytool log <submission-id> --keychain-profile brow-notary` lists why,
  usually something unsigned inside the bundle or a missing hardened runtime flag.
- **`make release` stops at "Set DEVELOPER_ID".** Step 4 above is missing.
- **Calendar access is denied in the shared build.** The entitlement in `Support/Brow.entitlements` must be on the
  signature: `codesign -d --entitlements - build/Brow.app` should list it.
- **Open at login does not stick.** macOS is more reliable about login items for apps that live in `/Applications`.
