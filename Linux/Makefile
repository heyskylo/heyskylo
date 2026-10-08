# Makefile — Linux x86_64 Kernel ROM
#
# Builds the Nyxian slot host image (`main`) and packages it with the Linux
# boot assets into a single `rom.zip` the Nyxian bootloader flashes into
# Library/Boot/Slot/A.
#
# The host image boots a real x86-64 Linux kernel inside rish's pure-Rust,
# JIT-less interpreter. Building requires a pinned rish checkout (for
# librish_ffi, the RUST static lib) and the guest kernel + initramfs staged
# under build/guest (see scripts/prepare-guest-images.sh).

SDK         := iphoneos
ARCH        := arm64
MIN_IOS     := 18.0
NAME        := main
MANIFEST    := manifest.plist
BOOT_LOGO   := assets/bootlogo.png
SRCDIR      := rom/src
ZSIGNDIR    := $(SRCDIR)/LindChain/ProcEnvironment/LiveContainer/ZSign
INCDIRS     := -Irom/src -Irom/stubs -Irom/include -I$(ZSIGNDIR) -I$(ZSIGNDIR)/common
FWFLAGS     := -From/frameworks
CC          := $(shell xcrun -sdk $(SDK) -f clang)
LD          := $(shell xcrun -sdk $(SDK) -f clang++)
SYSROOT     := $(shell xcrun -sdk $(SDK) --show-sdk-path)

# --- rish (pure-Rust, JIT-less x86-64 interpreter) ---------------------------
RISH_TARGET := aarch64-apple-ios
RISH_ROOT   ?= $(CURDIR)/build/rish
RISH_FFI    ?= $(RISH_ROOT)/target/$(RISH_TARGET)/release/librish_ffi.a

# --- pinned Linux guest images -----------------------------------------------
KERNEL_NAME := vmlinuz-virt-6.18.35
INITRD_NAME := rish-container.cpio
RISH_KERNEL ?= $(CURDIR)/build/guest/$(KERNEL_NAME)
RISH_INITRD ?= $(CURDIR)/build/guest/$(INITRD_NAME)
GUEST_STAMP := $(CURDIR)/build/guest/.prepared

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
               $(RISH_FFI) \
               -framework Foundation -framework UIKit -framework CoreFoundation \
               -framework CoreGraphics -framework QuartzCore -framework Security \
               -framework FrontBoard -framework OpenSSL -larchive

all: rom.zip

build/%.o: %
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(NAME): $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $(NAME)

# Build the Rust FFI static lib for the iOS device target. rish is a no-JIT
# interpreter; the guest instruction stream is decoded and interpreted, never
# executed natively.
$(RISH_FFI):
	@test -d "$(RISH_ROOT)" || { echo "error: rish checkout not found at $(RISH_ROOT) (set RISH_ROOT)"; exit 1; }
	cd "$(RISH_ROOT)" && cargo build --release --target $(RISH_TARGET) -p rish-ffi

build/guest/.prepared: scripts/prepare-guest-images.sh guest-images.lock.tsv
	scripts/prepare-guest-images.sh
	@touch $@

# The bootloader shows the manifest at flash time (NXRomBootLogo). Keep it
# readable and validate it the way CI does.
validate: $(MANIFEST)
	@command -v plutil >/dev/null 2>&1 || { echo "plutil required (macOS)"; exit 1; }
	plutil -lint $(MANIFEST)

rom.zip: $(NAME) $(MANIFEST) $(BOOT_LOGO) $(RISH_FFI) $(GUEST_STAMP)
	rm -rf .rompkg rom.zip
	mkdir -p .rompkg/ROM/assets .rompkg/ROM/kernel .rompkg/ROM/initramfs
	cp $(NAME) $(MANIFEST) .rompkg/ROM/
	cp $(BOOT_LOGO) .rompkg/ROM/assets/
	cp $(RISH_KERNEL) .rompkg/ROM/kernel/$(KERNEL_NAME)
	cp $(RISH_INITRD) .rompkg/ROM/initramfs/$(INITRD_NAME)
	cd .rompkg && zip -r ../rom.zip ROM
	rm -rf .rompkg

clean:
	rm -rf build .rompkg Application $(NAME) manifest.sign rom.zip
	rm -rf $(RISH_ROOT)/target/$(RISH_TARGET)/release/librish_ffi.a

.PHONY: all clean validate