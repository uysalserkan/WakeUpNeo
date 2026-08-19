APP_NAME    := WakeUpNeo
CONFIG      := release
BUNDLE_DIR  := build/$(APP_NAME).app
APP_DIR     := /Applications/$(APP_NAME).app
INFO_PLIST  := Sources/WakeUpNeo/Resources/WakeUpNeo-Info.plist
RESOURCES   := Sources/WakeUpNeo/Resources
TAP_REPO    := uysalserkan/tap
GITHUB_REPO := uysalserkan/WakeUpNeo

.PHONY: all help build bundle package install clean test brew-update

all: help

## help: Display available make targets
help:
	@echo "WakeUpNeo Build & Automation Tooling"
	@echo "======================================"
	@echo "  make build        - Compile the release executable with SwiftPM"
	@echo "  make test         - Run the complete 4-tier automated test suite (203 tests)"
	@echo "  make bundle       - Assemble and codesign the macOS .app bundle in ./build"
	@echo "  make package      - Create a distributable .zip archive and SHA256 checksum"
	@echo "  make install      - Build, bundle, and install WakeUpNeo to /Applications"
	@echo "  make brew-update  - Update Homebrew Cask in $(TAP_REPO) from GitHub release"
	@echo "  make clean        - Clean SwiftPM build artifacts and temporary files"
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

## package: create distributable zip archive and sha256 checksum in ./build
package: bundle
	cd build && zip -r -y $(APP_NAME)-macOS.zip $(APP_NAME).app
	cd build && shasum -a 256 $(APP_NAME)-macOS.zip > $(APP_NAME)-macOS.zip.sha256
	@echo "Packaged build/$(APP_NAME)-macOS.zip"
	@cat build/$(APP_NAME)-macOS.zip.sha256

## install: build and install into /Applications
install: bundle
	killall $(APP_NAME) 2>/dev/null || true
	rm -rf $(APP_DIR)
	cp -R $(BUNDLE_DIR) $(APP_DIR)
	@echo "Successfully installed $(APP_NAME) to $(APP_DIR)"

## brew-update: update Homebrew Cask formula in tap repository from GitHub release
brew-update:
	@set -e; \
	VERSION="$(VERSION)"; \
	if [ -z "$$VERSION" ]; then \
		echo "Fetching latest release version from GitHub..."; \
		TAG=$$(gh release view -R $(GITHUB_REPO) --json tagName -q .tagName 2>/dev/null || true); \
		if [ -z "$$TAG" ]; then \
			echo "Error: Could not determine latest GitHub release. Specify VERSION=x.y.z"; \
			exit 1; \
		fi; \
		VERSION=$${TAG#v}; \
	fi; \
	echo "Updating Homebrew Cask for $(APP_NAME) v$$VERSION..."; \
	SHA=""; \
	if [ -f "build/$(APP_NAME)-$$VERSION-macOS.zip.sha256" ]; then \
		SHA=$$(awk '{print $$1}' "build/$(APP_NAME)-$$VERSION-macOS.zip.sha256"); \
	fi; \
	if [ -z "$$SHA" ]; then \
		echo "Fetching SHA256 checksum from GitHub release assets..."; \
		SHA_FILE=$$(gh release download "v$$VERSION" -R $(GITHUB_REPO) -p "$(APP_NAME)-$$VERSION-macOS.zip.sha256" -O - 2>/dev/null || true); \
		SHA=$$(echo "$$SHA_FILE" | awk '{print $$1}'); \
	fi; \
	if [ -z "$$SHA" ]; then \
		echo "Downloading archive to compute SHA256..."; \
TMP_ZIP=$$(mktemp -t $(APP_NAME)).zip; \
		gh release download "$$VERSION" -R $(GITHUB_REPO) -p "$(APP_NAME)-$$VERSION-macOS.zip" -O "$$TMP_ZIP"; \
		SHA=$$(shasum -a 256 "$$TMP_ZIP" | awk '{print $$1}'); \
		rm -f "$$TMP_ZIP"; \
	fi; \
	if [ -z "$$SHA" ]; then \
		echo "Error: Failed to obtain SHA256 checksum for $(APP_NAME) v$$VERSION"; \
		exit 1; \
	fi; \
	echo "Version : $$VERSION"; \
	echo "SHA256  : $$SHA"; \
	TAP_PATH=$$(brew --repository $(TAP_REPO) 2>/dev/null || true); \
	if [ -z "$$TAP_PATH" ] || [ ! -d "$$TAP_PATH" ]; then \
		echo "Tapping $(TAP_REPO)..."; \
		brew tap $(TAP_REPO); \
		TAP_PATH=$$(brew --repository $(TAP_REPO)); \
	fi; \
	mkdir -p "$$TAP_PATH/Casks"; \
	CASK_FILE="$$TAP_PATH/Casks/wakeupneo.rb"; \
	echo "Writing $$CASK_FILE..."; \
	printf 'cask "wakeupneo" do\n  version "%s"\n  sha256 "%s"\n\n  url "https://github.com/%s/releases/download/v#{version}/WakeUpNeo-#{version}-macOS.zip"\n  name "WakeUpNeo"\n  desc "Native macOS menu bar utility to prevent sleep during critical tasks"\n  homepage "https://github.com/%s"\n\n  depends_on macos: :sequoia\n\n  app "WakeUpNeo.app"\n\n  postflight do\n    system_command "xattr",\n                   args: ["-dr", "com.apple.quarantine", "#{appdir}/WakeUpNeo.app"],\n                   sudo: false\n  end\n\n  zap trash: [\n    "~/Library/Application Support/com.wakeupneo.app",\n    "~/Library/Caches/com.wakeupneo.app",\n    "~/Library/Preferences/com.wakeupneo.app.plist",\n  ]\nend\n' "$$VERSION" "$$SHA" "$(GITHUB_REPO)" "$(GITHUB_REPO)" > "$$CASK_FILE"; \
	echo "Validating Cask syntax with Homebrew..."; \
	brew install --cask --dry-run "$$CASK_FILE"; \
	echo "Syncing changes to $(TAP_REPO)..."; \
	git -C "$$TAP_PATH" add Casks/wakeupneo.rb; \
	if git -C "$$TAP_PATH" diff --staged --quiet; then \
		echo "Homebrew Cask in $(TAP_REPO) is already up to date (v$$VERSION)."; \
	else \
		git -C "$$TAP_PATH" commit -m "Update wakeupneo cask to v$$VERSION"; \
		git -C "$$TAP_PATH" push origin main; \
		echo "Successfully updated Homebrew Cask to v$$VERSION!"; \
	fi

## clean: remove build artifacts
clean:
	swift package clean
	rm -rf build