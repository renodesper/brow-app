APP      := build/Brow.app
BINARY   := .build/release/Brow
# "-" is an ad-hoc signature. macOS ties the Calendar permission to the signature, and an ad-hoc one changes
# with every build, so the permission is asked again after each rebuild. To keep it, sign with your own
# identity:  make run SIGN_ID="Apple Development: you@example.com (TEAMID)"
# Or put it once in Makefile.local (not committed):  SIGN_ID := Apple Development: you@example.com (TEAMID)
# "security find-identity -v -p codesigning" lists the identities on this Mac.
# For a release others can open without a warning (docs/RELEASING.md): your "Developer ID Application" identity,
# and the profile made once with "xcrun notarytool store-credentials" (NOTARY_KEYCHAIN names the keychain it is in,
# when that is not the default one). All three also fit in Makefile.local.
-include Makefile.local
SIGN_ID        ?= -
DEVELOPER_ID   ?=
NOTARY_PROFILE ?= brow-notary
NOTARY_KEYCHAIN ?=
ENTITLEMENTS   := Support/Brow.entitlements
VERSION        := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
DMG            := build/Brow-$(VERSION).dmg

.PHONY: build bundle app run hardened dmg release test install clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/Brow
	cp Support/Info.plist $(APP)/Contents/Info.plist
	cp Support/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns

app: bundle
	codesign --force --sign "$(SIGN_ID)" $(APP)

# The app signed the way a release is (hardened runtime and entitlements), with your everyday identity, to see
# that it still works before spending a notarization on it. Open it with: open build/Brow.app
hardened: bundle
	codesign --force --options runtime --timestamp=none --entitlements $(ENTITLEMENTS) --sign "$(SIGN_ID)" $(APP)
	codesign --verify --strict --verbose=2 $(APP)

# A plain disk image, build/Brow-<version>.dmg, signed with SIGN_ID (ad-hoc unless you set one). Anyone who
# downloads it sees Gatekeeper's warning until it is a notarized release (below). This is what the GitHub release
# workflow publishes while there is no Developer ID.
dmg: app
	scripts/make-dmg.sh $(APP) $(DMG)

# A notarized disk image, build/Brow-<version>.dmg: the app signed with the Developer ID (hardened runtime and
# entitlements), the image signed too, notarized by Apple and stapled. Needs DEVELOPER_ID and a notarytool profile;
# see docs/RELEASING.md.
release: bundle
	@test -n "$(DEVELOPER_ID)" || { echo 'Set DEVELOPER_ID (see docs/RELEASING.md)'; exit 1; }
	codesign --force --options runtime --timestamp --entitlements $(ENTITLEMENTS) --sign "$(DEVELOPER_ID)" $(APP)
	codesign --verify --strict --verbose=2 $(APP)
	scripts/make-dmg.sh $(APP) $(DMG)
	codesign --force --timestamp --sign "$(DEVELOPER_ID)" $(DMG)
	xcrun notarytool submit $(DMG) --keychain-profile "$(NOTARY_PROFILE)" $(if $(NOTARY_KEYCHAIN),--keychain "$(NOTARY_KEYCHAIN)") --wait
	xcrun stapler staple $(DMG)
	xcrun stapler validate $(DMG)
	spctl --assess --type open --context context:primary-signature --verbose $(DMG)
	@echo "Ready to share: $(DMG)"

run: app
	-pkill -x Brow
	open $(APP)

test:
	swift test

install: app
	rm -rf /Applications/Brow.app
	cp -R $(APP) /Applications/

clean:
	rm -rf .build build
