XCODEBUILD = xcodebuild -scheme Avodoro -destination 'platform=macOS' -derivedDataPath build
APP = build/Build/Products/Debug/Avodoro.app

.PHONY: gen build test snapshot icon run clean

gen:
	xcodegen generate

build: gen
	$(XCODEBUILD) build

test: gen
	$(XCODEBUILD) test

snapshot: gen
	$(XCODEBUILD) test -only-testing:AvodoroTests/SnapshotTests

# Renders AppIconView into Sources/Avodoro/Assets.xcassets/AppIcon.appiconset.
icon: gen
	TEST_RUNNER_AVODORO_WRITE_ICON=1 $(XCODEBUILD) test -only-testing:AvodoroTests/AppIconTests

run: build
	open $(APP)

clean:
	rm -rf build snapshots Avodoro.xcodeproj
