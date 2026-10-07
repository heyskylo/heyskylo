# Makefile

SDK         := iphoneos
ARCH        := arm64
MIN_IOS     := 18.0
NAME        := main
ROM_MANIFEST  := manifest.plist
SRCDIR      := rom/src
ZSIGNDIR    := $(SRCDIR)/LindChain/ProcEnvironment/LiveContainer/ZSign
INCDIRS     := -Irom/src -Irom/stubs -Irom/include -I$(ZSIGNDIR) -I$(ZSIGNDIR)/common
FWFLAGS     := -From/frameworks
CC          := $(shell xcrun -sdk $(SDK) -f clang)
LD          := $(shell xcrun -sdk $(SDK) -f clang++)
SYSROOT     := $(shell xcrun -sdk $(SDK) --show-sdk-path)

HELLO_SRC   := appsrc/Hello/main.m
HELLO_PLIST := appsrc/Hello/Info.plist
HELLO_APP   := Application/Hello.app
HELLO_BIN   := $(HELLO_APP)/Hello

SRCS_ALL    := $(shell find $(SRCDIR) \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \))
SRCS        := $(filter-out \
               $(SRCDIR)/LindChain/ProcEnvironment/Shims/% \
               $(SRCDIR)/LindChain/ProcEnvironment/LiveContainer/Tweaks/% \
               $(SRCDIR)/LindChain/ProcEnvironment/LiveContainer/LCBootstrap.m, \
               $(SRCS_ALL))
OBJS        := $(SRCS:%=build/%.o)

CFLAGS      := -arch $(ARCH) -isysroot $(SYSROOT) -miphoneos-version-min=$(MIN_IOS) \
               -fobjc-arc -O2 -g -DHOST_ENV=1 -Wno-nonportable-include-path $(INCDIRS)
LDFLAGS     := -arch $(ARCH) -isysroot $(SYSROOT) -miphoneos-version-min=$(MIN_IOS) \
               -dynamiclib -install_name @rpath/$(NAME) \
               -rpath @executable_path/Frameworks $(FWFLAGS) \
               -framework Foundation -framework UIKit -framework CoreFoundation \
               -framework CoreGraphics -framework QuartzCore -framework Security \
               -framework FrontBoard -framework OpenSSL -larchive
HELLO_FLAGS := -arch $(ARCH) -isysroot $(SYSROOT) -miphoneos-version-min=$(MIN_IOS) \
               -fobjc-arc -Os -framework Foundation -framework UIKit

all: rom.zip

build/%.o: %
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(NAME): $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $(NAME)

$(HELLO_BIN): $(HELLO_SRC) $(HELLO_PLIST)
	rm -rf $(HELLO_APP)
	mkdir -p $(HELLO_APP)
	cp $(HELLO_PLIST) $(HELLO_APP)/Info.plist
	$(CC) $(HELLO_FLAGS) -dynamiclib -Wl,-install_name,@rpath/Hello $(HELLO_SRC) -o $(HELLO_BIN)

manifest.sign: $(NAME) $(HELLO_BIN)
	printf '%s\n' '$(NAME)' '$(HELLO_BIN)' > manifest.sign

rom.zip: $(NAME) $(HELLO_BIN) manifest.sign $(ROM_MANIFEST)
	rm -rf .rompkg rom.zip
	mkdir -p .rompkg/ROM
	cp $(NAME) manifest.sign $(ROM_MANIFEST) .rompkg/ROM/
	cp -R Application .rompkg/ROM/Application
	cd .rompkg && zip -r ../rom.zip ROM
	rm -rf .rompkg

clean:
	rm -rf build .rompkg Application $(NAME) manifest.sign rom.zip

# Lint the manifest against the keys the Nyxian bootloader (ROMManifest) requires.
validate:
	@command -v plutil >/dev/null 2>&1 || { echo "plutil required (macOS)"; exit 1; }
	plutil -lint $(ROM_MANIFEST)
	@for key in NXRomManifestVersion NXRomIdentifier NXRomName NXRomVersion NXRomMinimumNyxianVersion NXRomExecutable; do \
		plutil -extract "$$key" raw -o /dev/null $(ROM_MANIFEST) >/dev/null 2>&1 || { \
			echo "manifest.plist is missing required key: $$key"; exit 1; }; \
	done
	@[[ $$(plutil -extract NXRomManifestVersion raw -o - $(ROM_MANIFEST)) == "1" ]] || { \
		echo "NXRomManifestVersion must be 1 (current bootloader ABI)"; exit 1; }
	@echo "manifest.plist OK for Nyxian bootloader"

.PHONY: all clean validate
