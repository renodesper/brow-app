# Releasing Brow

Brow is released as a **disk image** (`Brow-<version>.dmg`: the app and a shortcut to `/Applications`), attached to a
GitHub release by a workflow. There are two kinds, and which one you get depends only on whether the repository has the
Apple Developer secrets (below):

| | Plain image (today) | Notarized image (once there is a Developer ID) |
|---|---|---|
| Signed with | ad-hoc | Developer ID Application, hardened runtime |
| Made by | `make dmg` | `make release` |
| Opens on another Mac | with Gatekeeper's warning (see "Opening a plain image") | with no warning |
| Calendar permission | asked again after every update, since an ad-hoc signature changes with each build | kept across updates |
| Needs | nothing | a paid Apple Developer account |

For your own Mac none of this is needed: `make run` is enough.

## Publishing a release (works today)

1. Raise `CFBundleShortVersionString` and `CFBundleVersion` in `Support/Info.plist`, merge that to `main`.
2. On GitHub: Releases → Draft a new release → choose a new tag `v<version>` (for example `v0.2.0`, matching the
   version you just set) → Publish release.
3. The **Release** workflow (`.github/workflows/release.yml`) runs on a macOS runner: it checks that the tag matches
   the version, runs the tests, builds the image and attaches `Brow-<version>.dmg` to the release (and keeps a copy as
   a workflow artifact). It takes a few minutes.
4. To try it without publishing anything: Actions → Release → Run workflow. The image is kept as an artifact only.

If the tag and the version disagree, the workflow stops with a message: raise the version, move the tag and publish
again. A repository that is private pays for macOS runner minutes at a higher rate than the free allowance; a public
one does not.

### Opening a plain image

The image is not notarized, so macOS warns that the developer cannot be verified. To open it: drag Brow to
Applications, open it once, and when it is refused go to System Settings → Privacy & Security, scroll down and press
"Open Anyway". Because the signature changes with each build, Calendar access is asked again after each update. Say
so in the release notes until there is a Developer ID.

## When there is an Apple Developer account

Nothing in the workflow has to change: it notices the secrets and switches to `make release` by itself.

1. **Join the Apple Developer Program** (paid, yearly). A free Apple ID can sign for development only.
2. **Make a "Developer ID Application" certificate.** Xcode → Settings → Accounts → your team → Manage Certificates →
   + → Developer ID Application. `security find-identity -v -p codesigning` then lists it as
   `Developer ID Application: Your Name (TEAMID)`.
3. **Export it**: Keychain Access → My Certificates → right-click the certificate → Export → `.p12`, with a password.
   Then `base64 -i developer-id.p12 | pbcopy`.
4. **Make an app-specific password** at account.apple.com (Sign-In and Security → App-Specific Passwords).
5. **Add five secrets** in the repository: Settings → Secrets and variables → Actions → New repository secret. You
   type them in; nothing is ever written to the repo.

   | Secret | Value |
   |---|---|
   | `DEVELOPER_ID_P12` | the base64 text of the `.p12` |
   | `DEVELOPER_ID_P12_PASSWORD` | the password you gave the `.p12` |
   | `DEVELOPER_ID_NAME` | `Developer ID Application: Your Name (TEAMID)` |
   | `NOTARY_APPLE_ID` | the Apple ID email |
   | `NOTARY_TEAM_ID` | the Team ID |
   | `NOTARY_PASSWORD` | the app-specific password from step 4 |

   (With all six set, the next release is notarized. If any is missing the workflow makes the plain image and says so
   in its log.)
6. **Try it first** with Actions → Release → Run workflow, then download the artifact and open it on another Mac. Then
   publish a release (a pre-release is a fine first one).

### On your own Mac

`make release` does the same by hand. Make the notarytool profile once (you type the password when asked):

```bash
xcrun notarytool store-credentials "brow-notary" --apple-id "you@example.com" --team-id "TEAMID"
```

and put this in `Makefile.local` (not committed):

```make
SIGN_ID        := Apple Development: Your Name (TEAMID)
DEVELOPER_ID   := Developer ID Application: Your Name (TEAMID)
NOTARY_PROFILE := brow-notary
```

`make release` signs the app (hardened runtime and `Support/Brow.entitlements`), makes the image, signs it, submits it
to Apple and waits, staples the ticket and checks it with `spctl`. `make hardened` is the same signature on the app with
your everyday identity, to see that it still works before spending a notarization (checked on 26 Nov 2026: it runs and
shows Calendar events).

## What is in the repo

- Bundle id `dev.bosan.Brow` (`Support/Info.plist`). Changing it later makes macOS treat the app as a new one: the
  Calendar permission and the login item would be asked for again. Settle it before the first notarized release.
- `Support/Brow.entitlements`: the Calendar entitlement. The hardened runtime, which notarization requires, only lets an
  app read Calendar with it. Nothing else is needed (no network, no sandbox, no scripting).
- `scripts/make-dmg.sh`: wraps an app in a plain image (`hdiutil`, no extra tool).
- `make dmg` and `make release`: as above. Neither has run in CI yet; `make dmg` was run and the image checked by
  mounting it.
- `.github/workflows/release.yml`: the workflow. The secrets path is written but has not run: it needs the account.

## If something goes wrong

- **The workflow stops at the tag check.** The tag is not `v` plus the version in `Support/Info.plist`.
- **Notarization says "Invalid".** `xcrun notarytool log <submission-id> --keychain-profile brow-notary` lists why,
  usually something unsigned inside the bundle or a missing hardened runtime flag.
- **`make release` stops at "Set DEVELOPER_ID".** `DEVELOPER_ID` is not set (locally, `Makefile.local`).
- **Calendar access is denied in the shared build.** The entitlement must be on the signature:
  `codesign -d --entitlements - build/Brow.app` should list it.
- **Open at login does not stick.** macOS is more reliable about login items for apps that live in `/Applications`.

## Homebrew

Brow is an app, so it goes in as a **cask** (a formula is for command-line tools and packages built from source).
`docs/homebrew/brow.rb` is a draft of the cask. It cannot be installed yet, because there is nothing to download.

### What has to exist first

1. **A notarized build.** Homebrew refuses casks for apps that fail Gatekeeper, so the plain image is not enough: it comes after "When there is an Apple Developer account".
2. **A public repository with a licence.** The cask downloads the image from a GitHub release by URL, which a private
   repo cannot serve (`renodesper/brow` is private and has no licence at the time of writing). The licence also tells
   people, and Homebrew, on what terms they may use the app.
3. **A GitHub release** named `v<version>` (for example `v0.2.0`) with `Brow-<version>.dmg` attached (the workflow does this). The
   release tag, the `version` in `Support/Info.plist` and the image's name must agree, since the cask builds the URL
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
shasum -a 256 build/Brow-0.2.0.dmg                               # put the result in `sha256`
cd "$(brew --repository renodesper/brow)"                        # edit Casks/brow.rb: version and sha256
brew audit --cask --new renodesper/brow/brow                     # style and structure checks
brew install --cask renodesper/brow/brow                         # needs the release to be downloadable
```

Then push that folder to a public GitHub repository called `homebrew-brow`. Run `brew install --cask` on a Mac that
has never had Brow, and check that it opens without a warning, asks for Calendar once, and that
`brew uninstall --cask brow` quits and removes it (`--zap` also removes its preferences).

### Each release

Raise `version` and `sha256` in the cask, in the tap, once the new release's image is up. `brew livecheck --cask brow`
reports when the repository has a newer release than the cask. This can be automated later (a workflow in the tap
that opens the pull request), but it is not needed for one app.

### Things to tell people

- Brow changes `statusLine` in `~/.claude/settings.json` when AI Usage for Claude Code is on, and puts it back when it
  is turned off. `brew uninstall` cannot do that for you, so turn it off in Settings → AI Usage before uninstalling
  (a backup is next to the file as `settings.json.brow-backup`). Say so in the README.
- "Open at login" is a login item the app registers itself. `brew uninstall` removes the app, and macOS then drops
  the login item.
