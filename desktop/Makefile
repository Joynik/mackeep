PROJECT := MackeepDesktop.xcodeproj
SCHEME := MackeepDesktop
DESTINATION := platform=macOS,arch=arm64

## The folder with the build products, it is inside the project
DERIVED_DATA := build
BUILT_PRODUCTS_DIR := $(DERIVED_DATA)/Build/Products/Debug

.PHONY: project build test run clean

## Generate the Xcode project from project.yml
project:
	xcodegen generate

## Build the application
build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination $(DESTINATION) -derivedDataPath $(DERIVED_DATA) build

## Run the tests
test: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination $(DESTINATION) -derivedDataPath $(DERIVED_DATA) test

## Run the application
run: build
	open "$(BUILT_PRODUCTS_DIR)/Mackeep.app"

## Remove the build products
clean:
	rm -rf $(PROJECT) $(DERIVED_DATA)
