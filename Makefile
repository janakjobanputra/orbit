.PHONY: generate build test run clean dmg testflight

generate:
	xcodegen generate

build: generate
	xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug -derivedDataPath build build

test: generate
	xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug -derivedDataPath build test

run: build
	-pkill -x Orbit
	open build/Build/Products/Debug/Orbit.app

clean:
	-xcodebuild -project Orbit.xcodeproj -scheme Orbit clean
	rm -rf build

dmg:
	scripts/release.sh dmg

testflight:
	scripts/release.sh testflight
