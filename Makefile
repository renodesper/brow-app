APP      := build/Brow.app
BINARY   := .build/release/Brow
# "-" is an ad-hoc signature. macOS ties the Calendar permission to the signature, and an ad-hoc one changes
# with every build, so the permission is asked again after each rebuild. To keep it, sign with your own
# identity:  make run SIGN_ID="Apple Development: you@example.com (TEAMID)"
# Or put it once in Makefile.local (not committed):  SIGN_ID := Apple Development: you@example.com (TEAMID)
# "security find-identity -v -p codesigning" lists the identities on this Mac.
# For a release others can open (docs/RELEASING.md): your "Developer ID Application" identity, and the profile
# made once with "xcrun notarytool store-credentials". Both also fit in Makefile.local.
-include Makefile.local
SIGN_ID        ?= -
DEVELOPER_ID   ?=
NOTARY_PROFILE ?= brow-notary
ENTITLEMENTS   := Support/Brow.entitlements
VERSION        := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
ZIP            := build/Brow-$(VERSION).zip

.PHONY: build bundle app run hardened release test install clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BINARY) $(APP)/Contents/MacOS/Brow
	cp Support/Info.plist $(APP)/Contents/Info.plist

app: bundle
	codesign --force --sign "$(SIGN_ID)" $(APP)

# The app signed the way a release is (hardened runtime and entitlements), with your everyday identity, to see
# that it still works before spending a notarization on it. Open it with: open build/Brow.app
hardened: bundle
	codesign --force --options runtime --timestamp=none --entitlements $(ENTITLEMENTS) --sign "$(SIGN_ID)" $(APP)
	codesign --verify --strict --verbose=2 $(APP)

# A notarized build, in build/Brow-<version>.zip. Needs DEVELOPER_ID and a notarytool profile; see docs/RELEASING.md.
release: bundle
	@test -n "$(DEVELOPER_ID)" || { echo 'Set DEVELOPER_ID (see docs/RELEASING.md)'; exit 1; }
	codesign --force --options runtime --timestamp --entitlements $(ENTITLEMENTS) --sign "$(DEVELOPER_ID)" $(APP)
	codesign --verify --strict --verbose=2 $(APP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	xcrun notarytool submit $(ZIP) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(APP)
	xcrun stapler validate $(APP)
	spctl --assess --type execute --verbose $(APP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	@echo "Ready to share: $(ZIP)"

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
