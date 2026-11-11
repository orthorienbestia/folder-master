HOST_ARCH := $(shell uname -m)
PROJECT := native/FolderMaster.xcodeproj
DERIVED := build/DerivedData

.PHONY: generate build universal test bridge-smoke presentation-smoke persistence-smoke script-proof script-isolation-proof ocr-proof check

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
	swiftc -target $(HOST_ARCH)-apple-macos14.0 -parse-as-library -module-cache-path build/SwiftModuleCache -import-objc-header native/Bridge/FolderMasterEngine.h native/FolderMaster/Shared/PersistentFolder.swift native/FolderMaster/Bridge/EngineClient.swift tests/native/BridgeSmoke.swift -L build/rust/Debug -lfolder_master_engine -liconv -lresolv -o build/bridge-smoke
	build/bridge-smoke

presentation-smoke: build
	swiftc -target $(HOST_ARCH)-apple-macos14.0 -parse-as-library -module-cache-path build/SwiftModuleCache -import-objc-header native/Bridge/FolderMasterEngine.h native/FolderMaster/Bridge/EngineClient.swift native/FolderMaster/Shared/PersistentFolder.swift native/FolderMaster/Shared/Experience.swift native/FolderMaster/AppModel.swift tests/native/AppModelSmoke.swift -L build/rust/Debug -lfolder_master_engine -liconv -lresolv -o build/presentation-smoke
	build/presentation-smoke

persistence-smoke: build
	swiftc -target $(HOST_ARCH)-apple-macos14.0 -parse-as-library -module-cache-path build/SwiftModuleCache -import-objc-header native/Bridge/FolderMasterEngine.h native/FolderMaster/Bridge/EngineClient.swift native/FolderMaster/Shared/PersistentFolder.swift tests/native/PersistentStoreSmoke.swift -L build/rust/Debug -lfolder_master_engine -liconv -lresolv -o build/persistence-smoke
	build/persistence-smoke

check:
	cargo fmt --all --check
	cargo clippy --offline --locked --workspace --all-targets -- -D warnings
	openspec validate build-folder-master --strict

script-proof: generate
	xcodebuild -quiet -project $(PROJECT) -scheme ScriptProof -configuration Debug -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=$(HOST_ARCH)' build
	'$(DERIVED)/Build/Products/Debug/FolderMasterScriptProof.app/Contents/MacOS/FolderMasterScriptProof'

# Acceptance gate, currently fails on permitted Launch Services Mach lookup.
# Keep the failure visible; do not treat the basic proof as full isolation.
script-isolation-proof: script-proof
	'$(DERIVED)/Build/Products/Debug/FolderMasterScriptProof.app/Contents/MacOS/FolderMasterScriptProof' --isolation

ocr-proof: generate
	xcodebuild -quiet -project $(PROJECT) -scheme OCRProof -configuration Debug -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=$(HOST_ARCH)' build
	python3 scripts/run-ocr-proof.py '$(DERIVED)/Build/Products/Debug/OCRProofHost.app'
