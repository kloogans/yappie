.PHONY: build run dev clean test

SCHEME = Yappie
BUILD_DIR = .build
ARCH = arm64

# Build directory (cached to avoid repeated showBuildSettings calls)
PRODUCTS_DIR = $(shell xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -configuration Debug -arch $(ARCH) -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')

build:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -configuration Debug -arch $(ARCH) build

# Run directly — shows debug output in terminal, Ctrl+C to quit
run: build
	@echo "--- Yappie Dev running (Ctrl+C to quit) ---"
	@"$(PRODUCTS_DIR)/Yappie Dev.app/Contents/MacOS/Yappie Dev"

# Run detached — opens normally like a regular app
open: build
	open "$(PRODUCTS_DIR)/Yappie Dev.app"

# Release build (for production)
release:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -configuration Release -arch $(ARCH) build

test:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) -arch $(ARCH) test

clean:
	xcodebuild -project Yappie.xcodeproj -scheme $(SCHEME) clean
	rm -rf $(BUILD_DIR)
