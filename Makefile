.PHONY: all build release test run clean app dmg package

all: build

build:
	@mkdir -p .tmp .clang-cache .module-cache
	TMPDIR=$$(pwd)/.tmp CLANG_MODULE_CACHE_PATH=$$(pwd)/.clang-cache SWIFT_MODULECACHE_OVERRIDE_DIRECTORY=$$(pwd)/.module-cache \
	swift build --disable-sandbox --scratch-path .build -Xswiftc -module-cache-path -Xswiftc $$(pwd)/.module-cache

release:
	@./scripts/build_app.sh

dmg:
	@./scripts/package_dmg.sh

package: dmg

test:
	@mkdir -p .tmp .clang-cache .module-cache
	TMPDIR=$$(pwd)/.tmp CLANG_MODULE_CACHE_PATH=$$(pwd)/.clang-cache SWIFT_MODULECACHE_OVERRIDE_DIRECTORY=$$(pwd)/.module-cache \
	swift build --build-tests --disable-sandbox --scratch-path .build -Xswiftc -module-cache-path -Xswiftc $$(pwd)/.module-cache && \
	xcrun xctest .build/arm64-apple-macosx/debug/mac-tool-kitPackageTests.xctest

run: build
	@.build/arm64-apple-macosx/debug/MacDashboardApp

app: release

clean:
	rm -rf .build .tmp .clang-cache .module-cache MacDashboard.app dist
