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

## Homebrew

Brow is an app, so it goes in as a **cask** (a formula is for command-line tools and packages built from source).
`docs/homebrew/brow.rb` is a draft of the cask. It cannot be installed yet, because there is nothing to download.

### What has to exist first

1. **A notarized build.** Homebrew refuses casks for apps that fail Gatekeeper, so everything above comes first.
2. **A public repository with a licence.** The cask downloads the zip from a GitHub release by URL, which a private
   repo cannot serve (`renodesper/brow` is private and has no licence at the time of writing). The licence also tells
   people, and Homebrew, on what terms they may use the app.
3. **A GitHub release** named `v<version>` (for example `v0.2.0`) with `build/Brow-<version>.zip` attached. The
   release tag, the `version` in `Support/Info.plist` and the zip's name must agree, since the cask builds the URL
   from `version`.

### Two places to publish it

- **Your own tap (start here).** A public repository named `homebrew-brow` holding `Casks/brow.rb`. No popularity
  requirement, and you decide when to update it. People install with:

  ```bash
  brew install --cask renodesper/brow/brow
  ```

- **The official `homebrew-cask`.** People install with `brew install --cask brow`. It takes a pull request to
  `Homebrew/homebrew-cask`, and the project has to be well enough known (the guidelines ask for a repository with a
  fair number of stars, forks and watchers), so this is the second step, once the app has users.

### Setting up the tap

```bash
brew tap-new renodesper/brow                                     # makes a local tap with the right layout
cp docs/homebrew/brow.rb "$(brew --repository renodesper/brow)/Casks/brow.rb"
shasum -a 256 build/Brow-0.2.0.zip                               # put the result in `sha256`
cd "$(brew --repository renodesper/brow)"                        # edit Casks/brow.rb: version and sha256
brew audit --cask --new renodesper/brow/brow                     # style and structure checks
brew install --cask renodesper/brow/brow                         # needs the release to be downloadable
```

Then push that folder to a public GitHub repository called `homebrew-brow`. Run `brew install --cask` on a Mac that
has never had Brow, and check that it opens without a warning, asks for Calendar once, and that
`brew uninstall --cask brow` quits and removes it (`--zap` also removes its preferences).

### Each release

Raise `version` and `sha256` in the cask, in the tap, once the new release's zip is up. `brew livecheck --cask brow`
reports when the repository has a newer release than the cask. This can be automated later (a workflow in the tap
that opens the pull request), but it is not needed for one app.

### Things to tell people

- Brow changes `statusLine` in `~/.claude/settings.json` when AI Usage for Claude Code is on, and puts it back when it
  is turned off. `brew uninstall` cannot do that for you, so turn it off in Settings → AI Usage before uninstalling
  (a backup is next to the file as `settings.json.brow-backup`). Say so in the README.
- "Open at login" is a login item the app registers itself. `brew uninstall` removes the app, and macOS then drops
  the login item.
