APP_NAME   := WakeUpNeo
CONFIG     := release
BUNDLE_DIR := build/$(APP_NAME).app
APP_DIR    := /Applications/$(APP_NAME).app
INFO_PLIST := Sources/WakeUpNeo/Resources/WakeUpNeo-Info.plist
RESOURCES  := Sources/WakeUpNeo/Resources

.PHONY: all help build bundle install clean test

all: help

## help: Display available make targets
help:
	@echo "WakeUpNeo Build & Automation Tooling"
	@echo "======================================"
	@echo "  make build    - Compile the release executable with SwiftPM"
	@echo "  make test     - Run the complete 4-tier automated test suite (203 tests)"
	@echo "  make bundle   - Assemble and codesign the macOS .app bundle in ./build"
	@echo "  make install  - Build, bundle, and install WakeUpNeo to /Applications"
	@echo "  make clean    - Clean SwiftPM build artifacts and temporary files"
	@echo ""

## build: compile the release executable with SwiftPM
build:
	swift build -c $(CONFIG)

## test: run full test suite
test:
	swift test

## bundle: assemble a proper .app bundle in ./build
bundle: build
	rm -rf $(BUNDLE_DIR)
	mkdir -p $(BUNDLE_DIR)/Contents/MacOS $(BUNDLE_DIR)/Contents/Resources
	cp .build/$(CONFIG)/$(APP_NAME) $(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)
	cp $(INFO_PLIST) $(BUNDLE_DIR)/Contents/Info.plist
	cp $(RESOURCES)/AppIcon.icns $(BUNDLE_DIR)/Contents/Resources/AppIcon.icns 2>/dev/null || true
	codesign --sign - --force --deep $(BUNDLE_DIR)
	@echo "Successfully assembled $(BUNDLE_DIR)"

## install: build and install into /Applications
install: bundle
	killall $(APP_NAME) 2>/dev/null || true
	rm -rf $(APP_DIR)
	cp -R $(BUNDLE_DIR) $(APP_DIR)
	@echo "Successfully installed $(APP_NAME) to $(APP_DIR)"

## clean: remove build artifacts
clean:
	swift package clean
	rm -rf build