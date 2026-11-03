.PHONY: build test format lint check hooks clean app install icon perf

# On Command Line Tools-only hosts, swiftlint needs TOOLCHAIN_DIR to find sourcekitd, and
# swift test needs the Testing macro plugin path passed explicitly (otherwise it is
# intermittently missing). Xcode hosts need neither.
DEVELOPER_DIR_PATH := $(shell xcode-select -p 2>/dev/null)
ifeq ($(DEVELOPER_DIR_PATH),/Library/Developer/CommandLineTools)
LINT_ENV := TOOLCHAIN_DIR=$(DEVELOPER_DIR_PATH)
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(DEVELOPER_DIR_PATH)/usr/lib/swift/host/plugins/testing
endif

build:
	swift build -c release --arch arm64

test:
	swift test $(TEST_FLAGS)

format:
	swiftformat .

lint:
	@command -v swiftformat >/dev/null || { echo "swiftformat is not installed (brew install swiftformat)"; exit 1; }
	@command -v swiftlint >/dev/null || { echo "swiftlint is not installed (brew install swiftlint)"; exit 1; }
	swiftformat --lint . && $(LINT_ENV) swiftlint lint --strict

check: test lint

hooks:
	scripts/install-hooks.sh

VERSION ?= 0.0.0
BUILD ?= 1

# Package dist/trrek.app (ad-hoc signed).
app:
	scripts/build-app.sh --version $(VERSION) --build $(BUILD)

# Install into ~/Applications and register with Launch Services.
install: app
	mkdir -p ~/Applications && rm -rf ~/Applications/trrek.app && cp -R dist/trrek.app ~/Applications/ && /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/trrek.app

# Generate dist/AppIcon.icns.
icon:
	scripts/make-icon.sh dist/AppIcon.icns

# Idle CPU/memory check of the installed (or dist) app; fails above 15 MB RSS.
perf:
	scripts/perf.sh

clean:
	rm -rf .build dist
