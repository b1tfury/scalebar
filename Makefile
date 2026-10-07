APP        := ScaleBar
BUNDLE     := build/$(APP).app
CONTENTS   := $(BUNDLE)/Contents
BIN        := .build/release/$(APP)
# Command Line Tools ship swift-testing but the macro plugin isn't auto-discovered.
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

.PHONY: build app run test install clean

build:
	swift build -c release

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BIN) $(CONTENTS)/MacOS/$(APP)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	cp scripts/garmin_push.py $(CONTENTS)/Resources/garmin_push.py
	codesign --force --sign - $(BUNDLE)
	@echo "Built $(BUNDLE)"

run: app
	open $(BUNDLE)

test:
	swift test $(TEST_FLAGS)

install: app
	rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/
	@echo "Installed /Applications/$(APP).app"

clean:
	rm -rf .build build
