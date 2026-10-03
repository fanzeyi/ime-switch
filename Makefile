APP := build/Build/Products/Release/IMESwitch.app

.PHONY: gen build run install clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project IMESwitch.xcodeproj -scheme IMESwitch -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build -quiet build

run: build
	-pkill -x IMESwitch
	open $(APP)

install: build
	-pkill -x IMESwitch
	rm -rf /Applications/IMESwitch.app
	cp -R $(APP) /Applications/
	open /Applications/IMESwitch.app

clean:
	rm -rf build IMESwitch.xcodeproj
