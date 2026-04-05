.PHONY: build run open clean test

SCHEME = Yappie
BUILD_DIR = .build
ARCH = arm64
PRODUCTS_DIR = $(shell xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -configuration Debug -arch $(ARCH) -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')

build:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -configuration Debug -arch $(ARCH) build

# Kill Yappie, copy to /Applications, launch via open, tail the log
run: build
	@pkill -x Yappie 2>/dev/null || true
	@sleep 0.5
	@rm -rf /Applications/Yappie.app
	@cp -R "$(PRODUCTS_DIR)/Yappie.app" /Applications/Yappie.app
	@> /tmp/yappie-debug.log
	@echo "--- Yappie launched. Tailing /tmp/yappie-debug.log (Ctrl+C to stop) ---"
	@open /Applications/Yappie.app
	@sleep 1
	@tail -f /tmp/yappie-debug.log

open: build
	@pkill -x Yappie 2>/dev/null || true
	@sleep 0.5
	open "$(PRODUCTS_DIR)/Yappie.app"

release:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -configuration Release -arch $(ARCH) build

test:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -arch $(ARCH) test

clean:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) clean
	rm -rf $(BUILD_DIR)
