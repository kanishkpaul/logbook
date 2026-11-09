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
PACKAGES := LogbookCore LogbookPersistence

.PHONY: build release run stop test test-core test-persistence format-check schema install spike-status clean

build:
	$(XCB) -configuration Debug build | grep -E 'error|warning: |BUILD' || true

release:
	$(XCB) -configuration Release build | grep -E 'error|warning: |BUILD' || true

run: build stop
	open -n $(APP)

stop:
	-pkill -x Logbook

test: test-core test-persistence

test-core:
	swift test --package-path Packages/LogbookCore

test-persistence:
	swift test --package-path Packages/LogbookPersistence

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

clean:
	rm -rf build $(addprefix Packages/,$(addsuffix /.build,$(PACKAGES)))
