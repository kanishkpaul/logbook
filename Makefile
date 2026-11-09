# logbook — stable commands for humans and agents.
# Packages test with `swift test` (fast); the app builds with xcodebuild.

PROJECT  := Logbook.xcodeproj
SCHEME   := Logbook
DD       := build/DD
APP      := $(DD)/Build/Products/Debug/Logbook.app
RELEASE  := $(DD)/Build/Products/Release/Logbook.app
# Package macros (StructuredQueries, Perception) need trusting; the CLI skips
# the prompt. In Xcode, click "Trust & Enable" once.
XCB      := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' \
            -derivedDataPath $(DD) -skipMacroValidation
PACKAGES := LogbookCore LogbookPersistence LogbookImport

.PHONY: build release run stop test test-core test-persistence test-import format-check schema install spike-status import-preview import-apply import-batches clean

build:
	$(XCB) -configuration Debug build | grep -E 'error|warning: |BUILD' || true

release:
	$(XCB) -configuration Release build | grep -E 'error|warning: |BUILD' || true

run: build stop
	open -n $(APP)

stop:
	-pkill -x Logbook

test: test-core test-persistence test-import

test-core:
	swift test --package-path Packages/LogbookCore

test-persistence:
	swift test --package-path Packages/LogbookPersistence

test-import:
	swift test --package-path Packages/LogbookImport

# Regenerates Packages/LogbookPersistence/schema.sql.
schema:
	swift test --package-path Packages/LogbookPersistence --filter regeneratesSchemaSQL

# Fails if the project file is not in canonical form (catches typos and hand edits).
format-check:
	@cp $(PROJECT)/project.xcproj build/.xcproj.check 2>/dev/null || (mkdir -p build && cp $(PROJECT)/project.xcproj build/.xcproj.check)
	@xcrun xcprojformatter --input build/.xcproj.check --output build/.xcproj.formatted
	@diff -u build/.xcproj.check build/.xcproj.formatted && echo "project.xcproj: formatted"

# One fixed install path keeps login-item and permission records stable.
install: release stop
	ditto $(RELEASE) /Applications/Logbook.app
	open /Applications/Logbook.app

# What the M0 spike recorded on its last launch.
spike-status:
	@cat "$(HOME)/Library/Application Support/logbook/spike-status.json"; echo

# Import the Notes shorthand (docs/IMPORT_FORMAT.md) into the live database.
#   make import-preview FILE=data/notes.md      (writes nothing)
#   make import-apply   FILE=data/notes.md      (one undoable batch)
#   make import-batches                          (list batches; undo with the CLI)
IMPORT := swift run --quiet --package-path Packages/LogbookImport logbook-import

import-preview:
	$(IMPORT) preview "$(FILE)" $(ARGS)

import-apply:
	$(IMPORT) apply "$(FILE)" $(ARGS)

import-batches:
	$(IMPORT) batches $(ARGS)

clean:
	rm -rf build $(addprefix Packages/,$(addsuffix /.build,$(PACKAGES)))
