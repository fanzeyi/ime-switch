APP := build/Build/Products/Release/IMESwitch.app
DIST_APP := build/dist/Build/Products/Release/IMESwitch.app
DIST_ZIP := build/IMESwitch.zip
# Created once with: xcrun notarytool store-credentials $(NOTARY_PROFILE) --apple-id <id> --team-id U75D75QN8A
NOTARY_PROFILE ?= IMESwitch

XCODEBUILD := xcodebuild -project IMESwitch.xcodeproj -scheme IMESwitch -configuration Release -destination 'generic/platform=macOS' -quiet

.PHONY: gen build run install dist clean

gen:
	xcodegen generate

build: gen
	$(XCODEBUILD) -derivedDataPath build build

run: build
	-pkill -x IMESwitch
	open $(APP)

install: build
	-pkill -x IMESwitch
	rm -rf /Applications/IMESwitch.app
	cp -R $(APP) /Applications/
	open /Applications/IMESwitch.app

# Developer ID signed, notarized and stapled build for distributing to others.
dist: gen
	$(XCODEBUILD) -derivedDataPath build/dist build \
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
