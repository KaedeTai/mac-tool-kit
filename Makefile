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
	swift test --disable-sandbox --scratch-path .build -Xswiftc -module-cache-path -Xswiftc $$(pwd)/.module-cache

run: build
	@"$$(swift build --disable-sandbox --scratch-path .build --show-bin-path)/MacDashboardApp"

app: release

clean:
	rm -rf .build .tmp .clang-cache .module-cache MacDashboard.app dist
