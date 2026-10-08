# Makefile — postmarketOS Phone ROM
#
# Builds the Nyxian slot host image (`main`) and packages it into `rom.zip`,
# which the Nyxian bootloader flashes into Library/Boot/Slot/A.
#
# The ROM host runs a QEMU/JIT VM (see engine.lock.tsv) that boots a real
# generic-x86_64 postmarketOS image with the Phosh phone DE — a kernel boot
# from a disk image, not a container. The guest image is intentionally NOT
# shipped in the ROM: on first boot the host downloads the pinned .img.xz,
# verifies its SHA-256, and decompresses it with the vendored XZ-Embedded
# decoder into the slot, then boots it.
#
# Requires macOS with Xcode (clang + iphoneos SDK). The guest image can be
# staged locally with `make guest` (needs curl + xz + shasum).

SDK         := iphoneos
ARCH        := arm64
MIN_IOS     := 18.0
NAME        := main
MANIFEST    := manifest.plist
BOOT_LOGO   := assets/bootlogo.png
SRCDIR      := rom/src
INCDIRS     := -Irom/src -Irom/src/xz
CC          := $(shell xcrun -sdk $(SDK) -f clang)
LD          := $(shell xcrun -sdk $(SDK) -f clang++)
SYSROOT     := $(shell xcrun -sdk $(SDK) --show-sdk-path)

SRCS        := $(shell find $(SRCDIR) \( -name '*.m' -o -name '*.c' \) | grep -v '^rom/src/engine/')
OBJS        := $(SRCS:%=build/%.o)

CFLAGS      := -arch $(ARCH) -isysroot $(SYSROOT) -miphoneos-version-min=$(MIN_IOS) \
               -fobjc-arc -O2 -g -Wno-nonportable-include-path $(INCDIRS)
LDFLAGS     := -arch $(ARCH) -isysroot $(SYSROOT) -miphoneos-version-min=$(MIN_IOS) \
               -dynamiclib -install_name @rpath/$(NAME) \
               -rpath @executable_path/Frameworks \
               -framework Foundation -framework UIKit -framework CoreFoundation -framework Metal -framework QuartzCore

all: rom.zip

build/%.o: %
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(NAME): $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $(NAME)

# The bootloader shows the manifest at flash time (NXRomBootLogo). Keep it
# readable and validate it the way CI does.
validate: $(MANIFEST)
	@command -v plutil >/dev/null 2>&1 || { echo "plutil required (macOS)"; exit 1; }
	plutil -lint $(MANIFEST)

# Stage the pinned guest image locally (download + verify + decompress).
guest: guest-images.lock.tsv
	scripts/prepare-guest-images.sh

rom.zip: $(NAME) $(MANIFEST) $(BOOT_LOGO)
	rm -rf .rompkg rom.zip
	mkdir -p .rompkg/ROM/assets
	cp $(NAME) $(MANIFEST) .rompkg/ROM/
	cp $(BOOT_LOGO) .rompkg/ROM/assets/
	cd .rompkg && zip -r ../rom.zip ROM
	rm -rf .rompkg

clean:
	rm -rf build .rompkg Application $(NAME) rom.zip

.PHONY: all clean validate guest