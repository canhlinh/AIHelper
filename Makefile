APP_NAME   = AIHelper
SCHEME     = AIHelper
BUILD_DIR  = build
RELEASE    = $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
INSTALL    = /Applications/$(APP_NAME).app

.PHONY: build run install clean kill restart

## Build a Release .app
build:
	xcodebuild \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'platform=macOS' \
		-derivedDataPath $(BUILD_DIR) \
		build 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)"

## Run the app directly from the build folder (no install)
run: build
	open $(RELEASE)

## Install to /Applications
install: build
	@echo "Installing to $(INSTALL)..."
	@rm -rf $(INSTALL)
	@cp -R $(RELEASE) $(INSTALL)
	@echo "Installed. Launching..."
	open $(INSTALL)

## Kill the running app
kill:
	@killall $(APP_NAME) 2>/dev/null && echo "Stopped $(APP_NAME)" || echo "$(APP_NAME) not running"

## Kill, rebuild, and relaunch
restart: kill build
	open $(RELEASE)

## Remove build artifacts
clean:
	rm -rf $(BUILD_DIR)
	@echo "Cleaned."
