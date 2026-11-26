APP      := build/Brow.app
BINARY   := .build/release/Brow
# "-" is an ad-hoc signature. macOS ties the Calendar permission to the signature, and an ad-hoc one changes
# with every build, so the permission is asked again after each rebuild. To keep it, sign with your own
# identity:  make run SIGN_ID="Apple Development: you@example.com (TEAMID)"
# Or put it once in Makefile.local (not committed):  SIGN_ID := Apple Development: you@example.com (TEAMID)
# "security find-identity -v -p codesigning" lists the identities on this Mac.
-include Makefile.local
SIGN_ID  ?= -

.PHONY: build app run test install clean

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BINARY) $(APP)/Contents/MacOS/Brow
	cp Support/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_ID)" $(APP)

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
