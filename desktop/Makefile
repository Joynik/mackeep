PROJECT := MackeepDesktop.xcodeproj
SCHEME := MackeepDesktop
DESTINATION := platform=macOS,arch=arm64

.PHONY: project build test run clean

## Generate the Xcode project from project.yml
project:
	xcodegen generate

## Build the application
build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination $(DESTINATION) build

## Run the tests
test: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination $(DESTINATION) test

## Run the application
run: build
	open build/Build/Products/Debug/Mackeep.app

## Remove the build products
clean:
	rm -rf $(PROJECT) build
