.PHONY: build run clean test

SCHEME = Yappie
BUILD_DIR = .build

build:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -configuration Debug build

run: build
	open "$$(xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -configuration Debug -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/Yappie.app"

test:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) test

clean:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) clean
	rm -rf $(BUILD_DIR)
