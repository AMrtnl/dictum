APP     := Dictum
CONFIG  ?= Debug
DERIVED := build/DerivedData
PRODUCT  = $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app
# Your Apple Development team, read from the keychain; empty means ad-hoc signing.
TEAM    ?= $(shell security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p' | head -1)
SIGNING  = $(if $(TEAM),CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=$(TEAM))

.PHONY: project build run install release stop open clean icon

project:
	@xcodegen generate --use-cache --quiet

build: project
	@xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' -quiet build $(SIGNING)

run: build stop
	@open $(PRODUCT)

# Release build copied to /Applications, then launched from there.
install: CONFIG = Release
install: build stop
	@rm -rf /Applications/$(APP).app
	@ditto $(PRODUCT) /Applications/$(APP).app
	@open /Applications/$(APP).app

# Release build zipped for GitHub Releases: build/Dictum.zip
release: CONFIG = Release
release: build
	@rm -f build/$(APP).zip
	@ditto -c -k --keepParent $(PRODUCT) build/$(APP).zip
	@echo "build/$(APP).zip"

stop:
	@pkill -x $(APP) || true
	@while pgrep -x $(APP) >/dev/null; do sleep 0.1; done

icon:
	@swift Scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset

open: project
	@open $(APP).xcodeproj

clean: stop
	rm -rf build $(APP).xcodeproj
