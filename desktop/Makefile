PROJECT := MackeepDesktop.xcodeproj
SCHEME := MackeepDesktop
DESTINATION := platform=macOS,arch=arm64

## The folder with the build products, it is inside the project
DERIVED_DATA := build
BUILT_PRODUCTS_DIR := $(DERIVED_DATA)/Build/Products/Debug
RELEASE_PRODUCTS_DIR := $(DERIVED_DATA)/Build/Products/Release

## The version of the application, the release of the tool writes it
VERSION := $(shell sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\(.*\)".*/\1/p' project.yml)

## The folder with the packages of the release
DIST_DIR := ../dist

## The folder where the disk image is built
STAGE_DIR := $(DERIVED_DATA)/package

.PHONY: project build release package test run clean

## Generate the Xcode project from project.yml
project:
	xcodegen generate

## Build the application
build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination $(DESTINATION) -derivedDataPath $(DERIVED_DATA) build

## Build the application for the release
##
## The version of the application is the version of the release, it is
## written in project.yml by the release of the tool.
##
## The extra flags of xcodebuild can be given in XCODEBUILD_FLAGS, e.g.
## XCODEBUILD_FLAGS="CODE_SIGN_IDENTITY=-" signs the application ad-hoc,
## when no certificate of the developer is there.
release: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination $(DESTINATION) -derivedDataPath $(DERIVED_DATA) \
		$(XCODEBUILD_FLAGS) build

## Package the application for the release
##
## The disk image holds the application and a link to the Applications
## folder, so the application can be dragged there.
package: release
	mkdir -p $(DIST_DIR)
	rm -rf $(STAGE_DIR)
	mkdir -p $(STAGE_DIR)
	ditto $(RELEASE_PRODUCTS_DIR)/Mackeep.app $(STAGE_DIR)/Mackeep.app
	ln -s /Applications $(STAGE_DIR)/Applications
	hdiutil create -volname Mackeep -srcfolder $(STAGE_DIR) -ov -format UDZO \
		$(DIST_DIR)/Mackeep-$(VERSION)-macos-arm64.dmg
	hdiutil verify $(DIST_DIR)/Mackeep-$(VERSION)-macos-arm64.dmg

## Run the tests
test: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination $(DESTINATION) -derivedDataPath $(DERIVED_DATA) \
		MACKEEP_BUNDLE_IDENTIFIER=com.joynik.mackeep.testing test

## Run the application
run: build
	open "$(BUILT_PRODUCTS_DIR)/Mackeep.app"

## Remove the build products
clean:
	rm -rf $(PROJECT) $(DERIVED_DATA)
