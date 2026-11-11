HOST_ARCH := $(shell uname -m)
PROJECT := native/FolderMaster.xcodeproj
DERIVED := build/DerivedData

.PHONY: generate build universal test bridge-smoke presentation-smoke check

generate:
	xcodegen generate --spec native/project.yml

build: generate
	xcodebuild -quiet -project $(PROJECT) -scheme FolderMaster -configuration Debug -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=$(HOST_ARCH)' build

universal: generate
	xcodebuild -quiet -project $(PROJECT) -scheme FolderMaster -configuration Debug -derivedDataPath $(DERIVED) -destination 'generic/platform=macOS' 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build

test: generate
	cargo test --offline --locked --workspace
	xcodebuild -quiet -project $(PROJECT) -scheme FolderMaster -configuration Debug -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=$(HOST_ARCH)' test

bridge-smoke: build
	swiftc -target $(HOST_ARCH)-apple-macos14.0 -parse-as-library -module-cache-path build/SwiftModuleCache -import-objc-header native/Bridge/FolderMasterEngine.h native/FolderMaster/Bridge/EngineClient.swift tests/native/BridgeSmoke.swift -L build/rust/Debug -lfolder_master_engine -liconv -lresolv -o build/bridge-smoke
	build/bridge-smoke

presentation-smoke: build
	swiftc -target $(HOST_ARCH)-apple-macos14.0 -parse-as-library -module-cache-path build/SwiftModuleCache -import-objc-header native/Bridge/FolderMasterEngine.h native/FolderMaster/Bridge/EngineClient.swift native/FolderMaster/Shared/Experience.swift native/FolderMaster/AppModel.swift tests/native/AppModelSmoke.swift -L build/rust/Debug -lfolder_master_engine -liconv -lresolv -o build/presentation-smoke
	build/presentation-smoke

check:
	cargo fmt --all --check
	cargo clippy --offline --locked --workspace --all-targets -- -D warnings
	openspec validate build-folder-master --strict
