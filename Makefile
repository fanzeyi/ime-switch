DEV_APP := build/Build/Products/Debug/IMESwitchDev.app
DIST_APP := build/dist/Build/Products/Release/IMESwitch.app
DIST_ZIP := build/IMESwitch.zip
# Created once with: xcrun notarytool store-credentials $(NOTARY_PROFILE) --apple-id <id> --team-id <team-id>
NOTARY_PROFILE ?= IMESwitch

XCODEBUILD := xcodebuild -project IMESwitch.xcodeproj -scheme IMESwitch -destination 'generic/platform=macOS' -quiet

.PHONY: gen build run install dist clean

gen:
	xcodegen generate

# Dev build: "IMESwitch Dev" (fan.zeyi.IMESwitch.dev), separate from the installed app.
build: gen
	$(XCODEBUILD) -configuration Debug -derivedDataPath build build

# Both would intercept ⌘Space, so stop the installed app while the dev build runs.
# Bring it back with `open /Applications/IMESwitch.app`.
run: build
	-pkill -x IMESwitch
	-pkill -x IMESwitchDev
	open $(DEV_APP)

# Installs the notarized build from `make dist`.
install:
	test -d $(DIST_APP) || $(MAKE) dist
	-pkill -x IMESwitch
	-pkill -x IMESwitchDev
	rm -rf /Applications/IMESwitch.app
	cp -R $(DIST_APP) /Applications/
	open /Applications/IMESwitch.app

# Developer ID signed, notarized and stapled build for distributing to others.
dist: gen
	rm -rf build/dist
	$(XCODEBUILD) -configuration Release -derivedDataPath build/dist build \
		CODE_SIGN_IDENTITY="Developer ID Application" OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
	codesign --verify --strict --deep $(DIST_APP)
	rm -f $(DIST_ZIP)
	ditto -c -k --keepParent $(DIST_APP) $(DIST_ZIP)
	xcrun notarytool submit $(DIST_ZIP) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DIST_APP)
	rm -f $(DIST_ZIP)
	ditto -c -k --keepParent $(DIST_APP) $(DIST_ZIP)
	@echo "Ready: $(DIST_ZIP)"

clean:
	rm -rf build IMESwitch.xcodeproj
