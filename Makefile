.PHONY: build run clean test

SCHEME = Yappie
BUILD_DIR = .build

build:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -configuration Debug -arch arm64 build

run: build
	open "$$(xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -configuration Debug -arch arm64 -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/Yappie.app"

test:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -arch arm64 test

clean:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) clean
	rm -rf $(BUILD_DIR)
