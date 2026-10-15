XCODEBUILD = xcodebuild -scheme Avodoro -destination 'platform=macOS' -derivedDataPath build
APP = build/Build/Products/Debug/Avodoro.app

.PHONY: gen build test snapshot run clean

gen:
	xcodegen generate

build: gen
	$(XCODEBUILD) build

test: gen
	$(XCODEBUILD) test

snapshot: gen
	$(XCODEBUILD) test -only-testing:AvodoroTests/SnapshotTests

run: build
	open $(APP)

clean:
	rm -rf build snapshots Avodoro.xcodeproj
