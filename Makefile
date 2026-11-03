.PHONY: build test format lint check hooks clean

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

clean:
	rm -rf .build dist
