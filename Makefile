# rock bsp
# (C) Copyright 2015, Radxa Limited
# support@radxa.com
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.
#

.PHONY: all clean help
.PHONY: tools ramdisk boot.img
.PHONY: uboot kernel rootfs nand.img emmc.img sdcard.img

include .config

HOST_ARCH:=$(shell uname -m )
DATE=$(shell date +"%y%m%d%H%M%S")
J=$(shell expr `grep ^processor /proc/cpuinfo  | wc -l`)
Q=

TOOLS_DIR=$(CURDIR)/tools
CROSS_COMPILE=$(TOOLS_DIR)/toolchain/bin/arm-eabi-

MODULE_DIR=$(ROCKDEV_DIR)/modules
KERNEL_SRC=$(CURDIR)/boards/$(BOARD)/linux-rockchip
UBOOT_SRC=$(CURDIR)/boards/$(BOARD)/u-boot-rockchip
INITRD_DIR=$(CURDIR)/boards/$(BOARD)/initrd
ROOTFS_DIR=$(CURDIR)/rootfs
ROCKDEV_DIR=$(CURDIR)/boards/$(BOARD)/rockdev

export TOOLS_DIR ROCKDEV_DIR MODULE_DIR
export KERNEL_SRC UBOOT_SRC INITRD_DIR

U_CONFIG_H=$(UBOOT_SRC)/include/config.h
K_BLD_CONFIG=$(KERNEL_SRC)/.config

U_BOOT_BIN=$(shell sed '/bootloader/!d' $(PACKAGE_FILE) | cut -f 2)
PARAMETER=$(CURDIR)/parameter/$(BOARD)-parameter
PACKAGE_FILE=$(CURDIR)/package-file/$(BOARD)-package-file
GIT_REV=$(shell git rev-parse --short HEAD)
IMAGE_NAME=$(BOARD)_$(shell echo $(BOARD_ROOTFS) | sed 's/\.[^ ]*/\_/g')$(DATE)_$(GIT_REV)

export PARAMETER PACKAGE_FILE U_BOOT_BIN

all: tools uboot kernel ramdisk rootfs boot.img $(IMAGE_TARGET)

clean:
	$(Q)$(MAKE) -C $(KERNEL_SRC) clean
	$(Q)$(MAKE) -C $(UBOOT_SRC) clean

$(KERNEL_SRC)/.git:
	$(Q)mkdir -p $(KERNEL_SRC)
	$(Q)git clone -n $(KERNEL_REPO) $(KERNEL_SRC)
	$(Q)cd $(KERNEL_SRC) && git checkout $(KERNEL_REV) && cd - > /dev/null

$(K_BLD_CONFIG): $(KERNEL_SRC)/.git
	$(Q)mkdir -p $(KERNEL_SRC)/modules
	$(Q)$(MAKE) -C $(KERNEL_SRC) ARCH=arm $(KERNEL_DEFCONFIG)

kernel: $(K_BLD_CONFIG)
	$(Q)$(MAKE) -C $(KERNEL_SRC) ARCH=arm oldconfig
	$(Q)$(MAKE) -C $(KERNEL_SRC) CROSS_COMPILE=$(CROSS_COMPILE) ARCH=arm -j$J
	$(Q)$(MAKE) -C $(KERNEL_SRC) $(KERNEL_EXTRA) CROSS_COMPILE=$(CROSS_COMPILE) ARCH=arm -j$J
	$(Q)$(MAKE) -C $(KERNEL_SRC) CROSS_COMPILE=$(CROSS_COMPILE) ARCH=arm INSTALL_MOD_PATH=$(MODULE_DIR) modules
	$(Q)$(MAKE) -C $(KERNEL_SRC) CROSS_COMPILE=$(CROSS_COMPILE) ARCH=arm INSTALL_MOD_PATH=$(MODULE_DIR) modules_install

linux-config: $(K_BLD_CONFIG)
	$(Q)$(MAKE) -C $(KERNEL_SRC) ARCH=arm menuconfig

rootfs:
	$(Q)mkdir -p $(ROCKDEV_DIR)/Image
ifneq ($(wildcard $(ROOTFS_DIR)/$(BOARD_ROOTFS)),)
	$(Q)wget -O $(ROOTFS_DIR)/$(BOARD_ROOTFS)) $(BOARD_ROOTFS_URL)
endif
	$(Q)rm -f $(ROCKDEV_DIR)/Image/rootfs.img
	$(Q)ln -sf $(ROOTFS_DIR)/$(BOARD_ROOTFS) $(ROCKDEV_DIR)/Image/rootfs.img

$(UBOOT_SRC)/.git:
	$(Q)mkdir -p $(UBOOT_SRC)
	$(Q)git clone -n $(UBOOT_REPO) $(UBOOT_SRC)
	$(Q)cd $(UBOOT_SRC) && git checkout $(UBOOT_REV) && cd - > /dev/null

$(U_CONFIG_H): $(UBOOT_SRC)/.git
	$(Q)mkdir -p $(UBOOT_SRC)
	$(Q)$(MAKE) -C $(UBOOT_SRC) mrproper
	$(Q)$(MAKE) -C $(UBOOT_SRC) CROSS_COMPILE=$(CROSS_COMPILE) ARCH=arm $(UBOOT_DEFCONFIG)
	$(Q)$(MAKE) -C $(UBOOT_SRC) $(UBOOT_EXTRA) CROSS_COMPILE=$(CROSS_COMPILE) ARCH=arm $(UBOOT_DEFCONFIG)

uboot: $(U_CONFIG_H)
	$(Q)$(MAKE) -C $(UBOOT_SRC) all CROSS_COMPILE=$(CROSS_COMPILE) ARCH=arm -j$J

$(INITRD_DIR)/.git:
	$(Q)mkdir -p $(INITRD_DIR)
	$(Q)git clone $(INITRD_REPO) $(INITRD_DIR)
	$(Q)cd $(INITRD_DIR) && git checkout $(INITRD_REV) && cd - > /dev/null
	$(Q)$(MAKE) -C $(INITRD_DIR)

#initrd.img
ramdisk: $(INITRD_DIR)/.git

tools/rockchip-mkbootimg/.git:
	$(Q)mkdir -p $(TOOLS_DIR)/rockchip-mkbootimg
	$(Q)git clone $(MKBOOTIMG_REPO) $(TOOLS_DIR)/rockchip-mkbootimg
	$(Q)cd $(TOOLS_DIR)/rockchip-mkbootimg && git checkout $(MKBOOTIMG_REV) && cd - > /dev/null
	$(Q)$(MAKE) -C $(TOOLS_DIR)/rockchip-mkbootimg install PREFIX=$(TOOLS_DIR)

tools/rkflashtool/.git:
	$(Q)mkdir -p $(TOOLS_DIR)/rkflashtool
	$(Q)git clone $(RKFLASHTOOL_REPO) $(TOOLS_DIR)/rkflashtool
	$(Q)cd $(TOOLS_DIR)/rkflashtool && git checkout $(RKFLASHTOOL_REV) && cd - > /dev/null
	$(Q)$(MAKE) -C $(TOOLS_DIR)/rkflashtool install PREFIX=$(TOOLS_DIR)

tools/toolchain/.git:
	$(Q)mkdir -p $(TOOLS_DIR)/toolchain
	$(Q)git clone -n --depth 1 $(TOOLCHAIN_REPO_$(HOST_ARCH)) $(TOOLS_DIR)/toolchain
	$(Q)cd $(TOOLS_DIR)/toolchain && git checkout $(TOOLCHAIN_REV_$(HOST_ARCH)) && cd - > /dev/null

#rock tools
tools: tools/toolchain/.git tools/rockchip-mkbootimg/.git tools/rkflashtool/.git

boot.img: tools kernel ramdisk
	$(Q)mkdir -p $(ROCKDEV_DIR)/Image
	$(Q)cp -vf $(KERNEL_SRC)/arch/arm/boot/zImage $(ROCKDEV_DIR)
	$(Q)cp -vf $(INITRD_DIR)/../initrd.img $(ROCKDEV_DIR)
ifneq ($(wildcard $(KERNEL_SRC)/resource.img),)
	$(Q)cp -vf $(KERNEL_SRC)/$(BOOTIMG_SECOND) $(ROCKDEV_DIR)
endif
	$(Q)cd $(ROCKDEV_DIR) && $(TOOLS_DIR)/bin/mkbootimg --kernel zImage --ramdisk initrd.img --second $(BOOTIMG_SECOND) -o Image/boot-linux.img && cd - > /dev/null

package-file: $(PACKAGE_FILE) uboot boot.img parameter rootfs

parameter: $(PARAMETER)

nand.img emmc.img: tools package-file
	$(Q)cp -v $(PARAMETER) $(ROCKDEV_DIR)/parameter
	$(Q)cp -v $(PACKAGE_FILE) $(ROCKDEV_DIR)/package-file
	$(Q)rm -f "$(ROCKDEV_DIR)/"*.bin
	$(Q)cp -vf $(UBOOT_SRC)/$(U_BOOT_BIN) $(ROCKDEV_DIR)
	$(Q)rm -f update_tmp.img
	$(Q)cd $(ROCKDEV_DIR) && $(TOOLS_DIR)/bin/afptool -pack ./ update_tmp.img && cd - > /dev/null
	$(Q)cd $(ROCKDEV_DIR) && $(TOOLS_DIR)/bin/img_maker -$(TYPECHIP) $(U_BOOT_BIN) 1 0 0 update_tmp.img $(IMAGE_NAME)_$@ && cd - > /dev/null
	$(Q)rm -f rockdev
	$(Q)ln -sf $(ROCKDEV_DIR) rockdev
	$(Q)echo "Image is at \033[1;36m$(ROCKDEV_DIR)/$(IMAGE_NAME)_$@\033[00m"

sdcard.img : uboot boot.img rootfs parameter
	$(Q)$(TOOLS_DIR)/scripts/hwpack.sh

update:
	$(Q)cd $(KERNEL_SRC) && git checkout $(KERNEL_REV) && cd - > /dev/null
	$(Q)cd $(UBOOT_SRC) && git checkout $(UBOOT_REV) && cd - > /dev/null

distclean:
	rm -f .config
	rm rockdev
	$(Q)$(MAKE) -C $(KERNEL_SRC) distclean
	$(Q)$(MAKE) -C $(UBOOT_SRC) distclean

mrproper:
	$(Q)$(MAKE) -C $(KERNEL_SRC) mrproper
	$(Q)$(MAKE) -C $(UBOOT_SRC) mrproper

help:
	@echo " ------------------------------------------- "
	@echo "		rockchip linux bsp"
	@echo " ------------------------------------------- "
	@echo " Usage:"
	@echo "  make			- Default 'make' pack all"
	@echo "  make	tools		- Builds open source tools,then install"
	@echo ""
	@echo "  Optional targets:"
	@echo "  make	linux-config	- make menuconfig"
	@echo "  make	uboot		- compile uboot"
	@echo "  make	kernel		- compile kernel"
	@echo "  make	ramdisk		- prepare initrd.img"
	@echo "  make	rootfs		- prepare rootfs"
	@echo ""
	@echo "Packages:"
	@echo "  make	boot.img	- prepare linux-boot.img"
	@echo "  make	nand.img	- generate nand.img"
	@echo "  make	emmc.img	- generate emmc.img"
	@echo "  make	sdcard.img	- generate sdcard.img"
	@echo ""
	@echo "  make	clean		- delete some compiled files"
	@echo "  make	distclean	- reply to original state"
	@echo "  make	update		- update the project"
	@echo ""
