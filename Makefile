.PHONY: build run open clean deepclean test

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
	arch -arm64 xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -destination 'platform=macOS' test

clean:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) clean
	rm -rf $(BUILD_DIR)

deepclean: clean
	@echo "Clearing DerivedData..."
	@rm -rf ~/Library/Developer/Xcode/DerivedData/Yappie-*
	@echo "Resetting Launch Services for Yappie..."
	@/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -u /Applications/Yappie.app 2>/dev/null || true
	@echo "Flushing preference caches..."
	@killall cfprefsd 2>/dev/null || true
	@echo "Deep clean complete."
