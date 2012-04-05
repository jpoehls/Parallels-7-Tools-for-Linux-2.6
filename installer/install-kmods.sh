#!/bin/sh
####################################################################################################
# @file install-kmods.sh
#
# Perform installation or removal of kernel modules.
#
# @author ayegorov@
# @author owner is alexg@
#
# Copyright (c) 2005-2008 Parallels Software International, Inc.
# All rights reserved.
# http://www.parallels.com
####################################################################################################

BASE_DIR="$(dirname "$0")"
PMANAGER="$BASE_DIR/pm.sh"

KMOD_DIR="$2"

BACKUP_DIR="$3"
BACKUP="$BACKUP_DIR/.kmods.list"

LOG_FILE="$4"

ARCH=$(uname -m)
KVER=$(uname -r)
KDIR="/lib/modules/$KVER/extra"
KVERH="/lib/modules/$KVER/build/include/linux/version.h"

PRL_MOD="prl_mod"
tools_modules_name="parallels-tools-kernel-modules"
FULL_PRODUCT_VERSION=$(cat "$KMOD_DIR/../version")
INSTALL_FULL_PRODUCT_VERSION=$(cat "$BASE_DIR/../version")

# extentions of kernel modules depend on version
if [ $(echo $KVER | cut -d'.' -f2) -eq 4 ]; then
	KEXT=o
else
	KEXT=ko
	BUILD_PRL_FREEZE="yes"
	BUILD_PRL_PV="yes"
fi
TGZEXT=tar.gz

####################################################################################################
# Definition of kernel modules to be installed
####################################################################################################

KMODS_PATHS="prl_eth/pvmnet                            \
             prl_tg/Toolgate/Guest/Linux/prl_tg        \
             prl_fs/SharedFolders/Guest/Linux/prl_fs   "
             
[ "x$BUILD_PRL_FREEZE" = "xyes" ] && KMODS_PATHS="$KMODS_PATHS prl_fs_freeze/Snapshot/Guest/Linux/prl_freeze"
[ "x$BUILD_PRL_PV"     = "xyes" ] && KMODS_PATHS="$KMODS_PATHS prl_pv/Paravirt/Linux/"

####################################################################################################
# Definition of error codes
####################################################################################################

E_NOERROR=0
E_NOPM=124   # defined in pm.sh
E_NOACT=141
E_NODIR=142
E_BFAIL=143
E_CFAIL=144
E_BUILD=145
E_KHEAD=146
E_MANAG=147
E_NOANS=148
E_NOPKG=149
E_CHKFAIL=150

####################################################################################################
# Show error
####################################################################################################

perror() {
	echo $1 1>&2
}

####################################################################################################
# Check requirements to install kernel modules
####################################################################################################

check_requirements() {
	# Check for precompiled kernel modules
	result_mod=$E_NOERROR
	if [ -n "$KMOD_DIR" ]; then
		kdir=$(ls "$KMOD_DIR" 2>/dev/null | grep "$KVER-$ARCH")
		for kmod_path in $KMODS_PATHS; do
			kmod=$(echo "$kmod_path" | sed -e "s#/.*##")
			fmod="$KMOD_DIR/$kdir/$kmod.$KEXT"
			if ([ -z "$kdir" ] || [ ! -e "$fmod" ]); then
				result_mod=$E_BUILD
				break
			fi
		done
	fi

	# Check... are there required package manager and packages?
	FLAG_CHECK_ASK="$FLAG_CHECK_ASK" "$PMANAGER" check_guest_tools
	packages=$?
	[ $packages -eq $E_NOERROR ] && return $E_NOERROR

	ans=""
	if [ "$FLAG_CHECK_ASK" = 'Yes' ]; then
		echo "Extra packages are required to setup Guest Tools kernel modules."
		echo "Would you like to install these packages automatically?"
		echo -n "Please, answer [yes/No] "

		read ans
	elif [ "$FLAG_CHECK_ASK" = 'Download' ]; then
		ans='Yes'
	else
		# Download/Install nothing, break with error
		echo "Following extra packages are required to setup Guest Tools kernel modules:"
		if [ $packages -ge 4 ]; then
			echo " - kernel sources"
			packages=$(($packages - 4)) 
		fi
		if [ $packages -ge 2 ]; then
			echo " - make"
			packages=$(($packages - 2)) 
		fi
		[ $packages -eq 1 ] && echo " - gcc"
		
		echo "Please install these components manually and rerun installer."
		return $E_NOPKG
	fi

	[ "x$ans" != "xYes" ] && [ "x$ans" != "xyes" ] && return $E_NOANS

	do_logging=
	[ -n "$LOG_FILE" ] && do_logging="--logfile"
	"$PMANAGER" $do_logging "$LOG_FILE" download_guest_tools
	result_pm=$?

	[ $result_mod -eq 0 ] || [ $result_pm -eq 0 ] && return $E_NOERROR
	[ $result_pm -eq $E_NOPM ] &&
		perror "Error: none of supported package managers found in system."
	return $E_CHKFAIL
}

####################################################################################################
# Remove kernel modules
####################################################################################################

remove_kernel_modules() {
	for kmod_path in $KMODS_PATHS; do
		kmod=$(echo "$kmod_path" | sed -e "s#/.*##")
		kmod_dir="$KMOD_DIR/$kmod"
		fmod="$KDIR/$kmod.$KEXT"

		echo "Start removal of $kmod kernel module"

		# Unload kernel module
		rmmod "$kmod" > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo "Kernel module $kmod was unloaded"
		else
			perror "Error: could not unload $kmod kernel module"
		fi

		# Remove kernel module from directory
		ls "$fmod" > /dev/null 2>&1 && rm -f "$fmod"

		# Remove kernel module reference in backup file
		sed -i -e "s#${fmod}##" -e "/^$/d" "$BACKUP"

		# Remove directory if it exists
		[ -d "$kmod_dir" ] && rm -rf "$kmod_dir"
	done

	if ([ -n "$FLAG_REMOVE_ALL" ] && [ -e "$BACKUP" ]); then
		echo "Remove kernel modules according to $BACKUP file"
		cat "$BACKUP" | while read line; do
			rm -f "$line"
		done
		rm -f "$BACKUP"
	fi

	# Removing dkms modules
	if type dkms > /dev/null 2>&1; then
		dkms remove -m $tools_modules_name -v $FULL_PRODUCT_VERSION --all > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo "DKMS modules were removed successfully"
		fi
	fi
}

####################################################################################################
# Install kernel modules
####################################################################################################

install_kernel_modules() {
	# Find an appropriate kernel modules' directory
	kernel_dir=$(ls "$KMOD_DIR" 2>/dev/null | grep "$KVER-$ARCH")

	make_flag=0

	for kmod_path in $KMODS_PATHS; do
		kernel_module_name=$(echo "$kmod_path" | sed -e "s#/.*##")
		found_module="$KMOD_DIR/$kernel_dir/$kernel_module_name.$KEXT"

		echo "Start installation of $kernel_module_name kernel module"

		# Check for precompiled kernel module
		if ([ -z "$kernel_dir" ] || [ ! -e "$found_module" ]); then

			if [ $make_flag -eq 0 ]; then
				# Unpack kernel module sources
				tar -xzf "$KMOD_DIR/$PRL_MOD.$TGZEXT" -C "$KMOD_DIR"

				# Build kernel module
				make -C "$KMOD_DIR" -f Makefile.kmods
				result=$?

				if [ $result -ne 0 ]; then
					perror "Error: could not build kernel modules"
					return $E_BFAIL
				fi

				make_flag=1
			fi

			kernel_dir="$KMOD_DIR/$kmod_path"
			found_module="$kernel_dir/$kernel_module_name.$KEXT"

			if [ ! -e "$found_module" ]; then
				perror "Error: could not find $kernel_module_name kernel module"
				return $E_BFAIL
			fi
		fi

		# Copy kernel module to destination directory
		cp -f "$found_module" "$KDIR"
		result=$?
		if [ $result -eq 0 ]; then
			echo "$KDIR/$kernel_module_name.$KEXT" >> "$BACKUP"
		else
			perror "Error: could not copy $found_module kernel module to $KDIR directory"
			return $E_CFAIL
		fi
	done

	if type dkms > /dev/null 2>&1; then
		dkms ldtarball --archive="$KMOD_DIR/$PRL_MOD.$TGZEXT" > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo "DKMS modules were added successfully"
		else
			echo "DKMS modules were not added"
		fi
		for _kver in `ls /lib/modules`; do
			dkms build -m $tools_modules_name -v $INSTALL_FULL_PRODUCT_VERSION -k $_kver > /dev/null 2>&1
			if [ $? -eq 0 ]; then
				echo "DKMS modules for kernel $_kver were built successfully"
			else
				echo "DKMS modules for kernel $_kver building failed"
			fi
			dkms install -m $tools_modules_name -v $INSTALL_FULL_PRODUCT_VERSION -k $_kver --force > /dev/null 2>&1
			if [ $? -eq 0 ]; then
				echo "DKMS modules for kernel $_kver were installed successfully"
			else
				echo "DKMS modules for kernel $_kver installation failed"
			fi
		done
	fi

	depmod -a
}

####################################################################################################
# Start installation or removal of kernel modules
####################################################################################################

case "$1" in
	-i | --install | -r | --remove)

		# Check directory with kernel modules
		if [ -z "$KMOD_DIR" ]; then
			perror "Error: directory with kernel modules was not specified"
			exit $E_NODIR
		fi

		# Check backup directory
		if [ -z "$BACKUP_DIR" ]; then
			perror "Error: backup directory was not specified"
			exit $E_NODIR
		fi

		# Make directory for extra kernel modules
		mkdir -p "$KDIR"

		if ([ "$1" = "-i" ] || [ "$1" = "--install" ]); then
			act="install"
			fact="Installation"
		else
			act="remove"
			fact="Removal"
		fi

		${act}_kernel_modules
		result=$?

		if [ $result -eq $E_NOERROR ]; then
			echo "${fact} of kernel modules was finished successfully"
		else
			perror "Error: failed to ${act} kernel modules"
		fi

		exit $result
		;;

	-c | --check)
		check_requirements
		exit $?
		;;
esac

exit $E_NOACT
