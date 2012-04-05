#!/bin/bash
#
# Script to make everybody happy

# Supported distributions:
#	- debian (ubuntu)
#	- redhat
#	- fedora
#	- mandrake
#	- suse

# Supported products:
#	- server
#	- workstation
#	- transporter
#	- sdk
#	- pmc
#	- gtools
#	- c2v

# Supported generic package names
#	- gcc
#	- make
#	- kheaders
#	- libc32
#	- alsa32
#	- alsa64
#	- nbd 
#	- dkms
#	- perl

PATH=${PATH:+$PATH:}/sbin:/bin:/usr/sbin:/usr/bin

# Script return codes
PM_OK=0
PM_NOT_FOUND=124
PM_LOCKED=123
PM_FAILED=3

# Globals
target_product=''
logfile=''
lib_deps_file=''
karch=$(uname -m)

# Some variables for check_precomp_kmods
	BASE_DIR="$(dirname "$0")"
	KMOD_DIR="$BASE_DIR/../kmods"

	KMODS_PATHS="prl_eth/pvmnet                         \
             prl_tg/Toolgate/Guest/Linux/prl_tg        \
             prl_fs/SharedFolders/Guest/Linux/prl_fs"

package_manager()
{
	type yum >/dev/null 2>&1 
	if [ $? -eq 0 ] ; then 
		echo "yum"
		return 0
	fi
	
	type apt-get >/dev/null 2>&1 
	if [ $? -eq 0 ] ; then 
		#don't use old apt-get
		ver=$(apt-get -v | grep -m 1 apt)
		ver=${ver#* }
		#compare with 0.6.
		echo $ver | grep -q "^0\.[0-5]\."
		rc1=$?
		if [ $rc1 -ne 0 ] ; then
			echo "apt-get"
			return 0
		fi
	fi

	# TODO up2date for redhat enterprise <= 4 

	# yast is unsupported

	# zypper for suse > 10.1
	type zypper >/dev/null 2>&1
	if [ $? -eq 0 ] ; then 
		echo "zypper"
		return 0
	fi

	# TODO rug in sles/sled, suse <= 10.1

	type urpmi >/dev/null 2>&1
	if [ $? -eq 0 ] ; then 
		echo "urpmi"
		return 0
	fi
	
	return 1
}


# Prints package name $1 specific to distro $2 of version $3
# Returns:
# 0 - package name mapping was found successfully
# 1 - mapping was not found
# 2 - some other error
map_package_name()
{
	local package_name=$1
	local os_name=$2
	local os_version=$3

	case "$package_name" in
		gcc)
			echo "gcc"
		;;

		make)
			echo "make"
		;;

		kheaders)
			local kver=$(uname -r)
			case "$os_name" in
				debian)
					echo "linux-headers-${kver}"
				;;
				redhat|fedora)
					if [ -d /lib/modules/$kver ]; then
						kernel_package=$(rpm -qf /lib/modules/$kver)
						echo $kernel_package | sed "s/kernel\(-[a-zA-Z\-]*\)/kernel\1devel-/"
					else
						return 1
					fi
				;;
				suse)
					# sample: uname -r = 2.6.25.9-0.2-default
					# but package version is 2.6.25.9-0.2
					kver=$(echo $kver | sed -e "s/\(.*\)-[a-z]*/\1/g")
					echo "kernel-source=${kver}"
				;;
				mandrake)
					# for 2008.0 & 2008.1 - kernel-devel
					# for older and newer - need to investigate
					echo "kernel-devel"
				;;
				*)
					echo "kernel headers"
					return 1
				;;
			esac
		;;

		libc32)
			case "$os_name" in
				debian)
					echo "libc6-i386"
				;;
				redhat|fedora)
					if [ "$os_name" = "fedora" -a $os_version -ge 11 -o \
						 "$os_name" = "redhat" -a $os_version -ge 6 ]; then
						echo "glibc.i686"
					else
						echo "glibc.i386"
					fi
				;;
				suse)
					echo "glibc-32bit"
				;;
				mandrake)
					echo "glibc6"
				;;
				*)
					echo "32-bit glibc"
					return 1
				;;
			esac
		;;

		alsa32)
			# alsa32 can be requested both for 32- and 64-bit systems.
			# If on 64-bit system alsa is already installed need to try
			# to install 32-bit of exactly the same version.
			# If on 64-bit system there's no alsa of any bitness let's
			# install package without specifying version because recent one
			# should be used by package management system.
			case "$os_name" in
				debian)
					# 32-bit version has strict dependency on 64-bit
					test "_$karch" = "_x86_64" &&
						echo "lib32asound2" ||
						echo "libasound2"
				;;
				redhat|fedora)
					# check if 64-bit version is installed
					alsalib=$(rpm -q alsa-lib.x86_64 2>/dev/null)
					# strip out x86_64 suffix
					test $? -eq 0 -a -n "$alsalib" &&
						alsalib="${alsalib%.x86_64}" ||
						alsalib=alsa-lib
					if [ "$os_name" = "fedora" -a $os_version -ge 11 -o \
						 "$os_name" = "redhat" -a $os_version -ge 6 ]; then
						echo "${alsalib}.i686"
					else
						echo "${alsalib}.i386"
					fi
				;;
				suse)
					if [ "_$karch" = "_x86_64" ]; then
						alsalib=$(rpm -q libasound2 2>/dev/null)
						test $? -eq 0 -a -n "$alsalib" &&
							ver="=$(echo "$alsalib" | sed 's/^libasound2-//')" ||
							ver=
						echo "libasound2-32bit$ver"
					else
						echo "libasound2"
					fi
				;;
				mandrake)
					# TODO Strict version install is not implemented
					echo "libalsa2"
				;;
				*)
					echo "32-bit libasound"
					return 1
				;;
			esac
		;;

		alsa64)
			# Is expected to be requested only on 64-bit systems. The same thing with version
			# as for alsa32.
			case "$os_name" in
				debian)
					echo "libasound2"
				;;
				redhat|fedora)
					# check if 32-bit version is installed
					alsalib=$(rpm -q alsa-lib 2>/dev/null)
					# strip out suffix
					test $? -eq 0 -a -n "$alsalib" &&
						alsalib="${alsalib%.i?86}" ||
						alsalib=alsa-lib
					echo "${alsalib}.x86_64"
				;;
				suse)
					alsalib=$(rpm -q libasound2-32bit 2>/dev/null)
					test $? -eq 0 -a -n "$alsalib" &&
						ver="=$(echo "$alsalib" | sed 's/^libasound2-32bit-//')" ||
						ver=
					echo "libasound2$ver"
				;;
				mandrake)
					echo "libalsa2"
				;;
				*)
					echo "64-bit libasound"
					return 1
				;;
			esac
		;;

		nbd)
			if [ "$os_name" = "debian" ]; then
				echo "nbd-client"
			else
				echo "nbd"
			fi
		;;

		dkms)
			echo "dkms"
		;;

		perl)
			case "$os_name" in
				debian)
					echo "perl-base"
				;;
				redhat|fedora)
					echo "perl"
				;;
				suse)
					[ $os_version -ge 11 ] && echo "perl-base" || echo "perl"
				;;
				mandrake)
					echo "perl-base"
				;;
				*)
					echo "perl"
					return 1
				;;
			esac
		;;

		*)
			# unknown/unsupported package
			return 1
		;;
	esac

	return 0
}


# Tries to map library name into package name relying on package manager
map_libpackage_name()
{
	pm=`package_manager`
	libname=$1

	case "$pm" in
		yum)
			local postfix=""
			local arch=$(uname -m)
			[ "$arch" == "x86_64" ] && postfix="()(64bit)"

			# the library architecture should specified be for yum
			yum_output=`LANG=C yum provides -q "${libname}${postfix}" 2>/dev/null`
			rc=$?
			test $rc -eq 0 || return $PM_FAILED

			# no matching was found
			test -z "$yum_output" && return $PM_FAILED

			# trying to pick out package name from yum's mass of output
			packages_list=$(echo "$yum_output" | grep ':' |
				egrep -v '^(Other|Matched from)' |
				grep -v '^[[:space:]]*:' |
				grep -v '^Repo' |
				sed 's/^\(.*\) :.*/\1/')
			result_package=$(echo "$packages_list" | head -n 1)
			# trying to find newest package in the repository
			IFS=$'\n'
			for package in $packages_list; do
				[ "$package" \> "$result_package" ] && result_package=$package
			done
			unset IFS
			echo $result_package
			return $PM_OK
		;;

		apt-get)
			# hueristics (or may be policy?) for debian-based distros:
			#  libName.so.N -> libnameN
			lib_name=`echo "$libname" | cut -d. -f1 | LANG=C tr '[[:upper:]]' '[[:lower:]]'`
			lib_ver=`echo "$libname" | cut -d. -f3`
			# if library name ends with number - add dash to separate it from lib version
			echo "${lib_name:${#lib_name}-1}" | grep -q '[0-9]' && \
				lib_name="${lib_name}-"
			echo "${lib_name}${lib_ver}"
			return $PM_OK
		;;

		zypper)
			# if zypper has capability option - use it, otherwise don't know how to map
			zypper_output=`zypper wp "${libname}" 2>/dev/null`
			rc=$?
			test $rc -eq 0 || return $PM_FAILED
			echo "$zypper_output" | tail -n1 | awk '{print $3}'
			return $PM_OK
		;;

		urpmi)
			# just asking urmpq to find rpm name
			urpmq -p "$libname" 2>/dev/null
			test $? -eq 0 && return $PM_OK
			return $PM_FAILED
		;;

		*)
			perror "Unknown utility for automatical download packages"
			# we must use return instead of abort to allow
			# showing of uninstalled packages instead of just strange error
			# (e.g. packages func will be called next)
			return 1
		;;
	esac
}


# Check if all packages listed in $1 installed on system where rpm presented.
# Using for fixing problems appeared when yum or zypper return success return 
# code when repository is not avalable or requires package is absent in repo.
rpm_check_installed()
{
	for package in $1; do
		# In case of suse we may append exact version with '=':
		#   "pkg_name=pkg_version"
		# With such form of name we are not able to query it by rpm
		# and need to replace it with "pkg_name-pkg_verson*" which works.
		echo "$package" | grep -q '=' && package="${package/=/-}*"
		rpm -q "$package" >/dev/null 2>&1 || return 1
	done
}

# Install packages listed in $2 using package manager $1.
# All output is appended to file $3 (if not null).
# Returns:
# {yes, this script returns something TODO}
pm_install()
{
	local pm=$1
	local list="$2"
	local output="$3"

	test -z $output && output=/dev/stdout

	case "$pm" in
		yum)
 			kill -0 $(cat '/var/run/yum.pid' 2> /dev/null) > /dev/null 2>&1
 			if [ $? -ne 0 ];
			then
				yum -y install $list >> $output 2>&1
				rpm_check_installed "$list" || return $PM_FAILED
				return $PM_OK
 			fi
 			return $PM_LOCKED
		;;

		apt-get)
			local dpkg_lockfile='/var/lib/dpkg/lock'
			test -f "$dpkg_lockfile" && \
				grep -q $(stat -c %i "$dpkg_lockfile") /proc/locks && \
 				exit $PM_LOCKED

			local src_list='/etc/apt/sources.list'
			local need_check_src=0
			if grep -qs '^[[:space:]]*deb[[:space:]]\+cdrom:' "$src_list"; then
				# cdroms is in sources configuration
				# need to check if it is mounted before apt-get call
				# otherwise it will stall promting to insert disk
				need_check_src=1

				# so let's gather disk lables of all mounted cdroms
				local disk_labels=
				IFS=$'\n'
				for mnt_pt in $(df -P -t iso9660 2> /dev/null | sed '1d' | awk '{print $6}'); do
					disk_info="$mnt_pt"/.disk/info
					test -r "$disk_info" || continue
					# double quotes should be replaced by underscores
					# as it is done in output of apt-get
					disk_labels="$disk_labels$(cat "$disk_info" | tr '"' '_')"$'\n'
				done
				unset IFS
			fi

			# Don't fail if 'apt-get update' return not succeed code
			# because the main task is to install packages and
			# 'apt-get install' can work even if update failed
			apt-get -q update >> $output 2>&1
			echo "Return code from apt-get update is $?" >> $output 2>&1

			retcode=0
			for pkg in $list;
			do
				local rc=0
				if [ $need_check_src -eq 1 ]; then
					msg=$(
						apt-get install -y -q --print-uris $pkg | grep "^'cdrom:\[" | \
						sed "s/^'cdrom:\[\(.*\)\].*/\1/" | \
						while read label; do
							# check each required label
							if ! echo "$disk_labels" | grep -q "$label"; then
								echo "Disk with label \"$label\" is not mounted"
								echo " - skipping package $pkg"
								break
							fi
						done
					)
					if [ -n "$msg" ]; then
						echo "$msg" >> $output
						rc=1
					fi
				fi

				test $rc -eq 0 && apt-get -q -qq --allow-unauthenticated install "$pkg" \
					>> $output 2>&1
				rc=$?
				# will just save the first error retcode
				test $retcode -eq 0 && retcode=$rc
			done
			test $retcode -eq 0 && return $PM_OK
			return $PM_FAILED
		;;

		zypper)
			kill -0 $(cat '/var/run/zypp.pid' 2> /dev/null) > /dev/null 2>&1
			if [ $? -ne 0 ];
			then
				zypper_opt="install -y"
				# Detect that options 'non-inveractive' and 'no-gpg-checks'
				# are supported by current version of zypper.
				for mode in 'non-interactive' 'no-gpg-checks';
				do
					LANG=C zypper --$mode 2>/dev/null |
						grep -q "Entering '\?$mode'\? mode" &&
							zypper_opt="--$mode $zypper_opt"
				done
				# Use 'capability' option starting for zypper 0.8
				zypper_ver=($(zypper --version 2>&1 | sed 's/^zypper \([0-9]*\)\.\([0-9]*\)\..*$/\1 \2/'))
				if [ ${zypper_ver[0]} -eq 0 -a ${zypper_ver[1]} -lt 8 ]; then
					list="$(echo $list | sed -e 's/kernel-source[^\ ]*/kernel-source/')" 
				else
					zypper_opt="$zypper_opt --capability"
				fi
				for pkg in $list; do
					zypper $zypper_opt $pkg >> $output 2>&1
				done
				rpm_check_installed "$list" || return $PM_FAILED
				return $PM_OK
			fi
			exit $PM_LOCKED
		;;
		urpmi)
			local urpmi_lockfile='/var/lib/urpmi/.LOCK'
			if [ ! -f "$urpmi_lockfile"  ] ||
				! grep -q $(stat -c %i "$urpmi_lockfile") /proc/locks;
			then
				urpmi --auto $list >> $output 2>&1

				#if [ "$IS_KHEAD" != "0" ]
				#then
				#	# Just a small help for poor user
				#	# to avoid awful Mandriva's problem
				#	KSCR_0="/lib/modules/$(uname -r)/build"
				#	KSCR_1='/usr/src/linux'
				#	LINUX_FILE='include/linux/version.h'
				#	test ! -f "$KSRC_0/$LINUX_FILE" &&
				#		test -f "$KSRC_1/$LINUX_FILE" &&
				#			ln -s $KSRC_1 $KSRC_0
				#fi

				test $? -eq 0 && return $PM_OK
				return $PM_FAILED
			fi
			exit $PM_LOCKED
		;;

		*)
			error "Unknown utility for automatical download packages"
			# we must use return instead of abort to allow
			# showing of uninstalled packages instead of just strange error
			# (e.g. packages func will be called next)
			return 1
		;;
	esac
}


perror () {
	echo "${@}" 1>&2
}


pm_help ()
{
	help_text=`cat <<EOF
Usage: pm.sh [OPTIONS]

This utility is capable for managing packages Parallels products for Linux are depends on.
Main actions are checking for packages in system and installing them automatically.

Options:
    -c, --check PRODUCT       Prints list of packages needed to install for PRODUCT
    -i, --install PRODUCT     Installs packages needed for PRODUCT
    -l, --logfile FILENAME    Print all output from package manager into FILENAME
                              instead of stdout
        --lib-deps FILENAME   File with libraries which dependences should be resolved
    -h, --help                Print this help

Supported products:
    server
    workstation
    sdk          (Parallels Virtualization SDK)
    pmc          (Parallels Management Console)
    gtools       (Parallels Guest Tools for Linux)
    transporter  (Parallels Transporter Agent)
    c2v          (Parallels Transporter for Containers)
EOF`
	echo "$help_text" 1>&2
}


pm_parse_cmdline()
{
	while true; do
		case "${1}" in
			--check | -c)
				if [ "x${2}" = "x" ]; then
					perror "Missing argument to option: '${1}'"
					perror

					pm_help
					exit 1
				fi

				action='check'
				target_product="${2}"
				shift 2
				;;
			--install | -i)
				if [ "x${2}" = "x" ]; then
					perror "Missing argument to option: '${1}'"
					perror

					pm_help
					exit 1
				fi

				action='install'
				target_product="${2}"
				shift 2
				;;
			--logfile | -l)
				if [ "x${2}" = "x" ]; then
					perror "Missing argument to option: '${1}'"
					perror

					pm_help
					exit 1
				fi

				logfile="${2}"
				shift 2
				;;
			--lib-deps)
				if [ "x${2}" == "x" ]; then
					perror "Missing argument to option: '${1}'"
					perror

					pm_help
					exit 1
				fi

				lib_deps_file="${2}"
				shift 2
				;;
			--help | -h)
				pm_help
				exit 0
				;;
			check_guest_tools)
				# For compatibility
				action='check_old'
				target_product='gtools'
				shift 1
				;;
			download_guest_tools)
				# For compatibility
				action='download_old'
				target_product='gtools'
				shift 1
				;;
			*)
				if [ "x${1}" != "x" ]; then
					perror "Unknown option: '${1}'"
					perror

					pm_help
				else
					break
				fi
				exit 1
				;;
		esac			
	done
}


detect_os_name()
{
	if [ -f "/etc/lsb-release" ] ; then
		egrep -q -i "debian|ubuntu" /etc/lsb-release
		if [ $? -eq 0 ] ; then
			echo "debian" #and ubuntu
			return 0
		fi
	fi

	if [ -f "/etc/debian_version" -a ! -f "/etc/xandros-desktop-version" ] ; then
		echo "debian"
		return 0
	fi


	if [ -f "/etc/fedora-release" ] ; then
		echo "fedora"
		return 0
	fi

	if [ -f "/etc/mandrake-release" -o -L "/etc/mandriva-release" ] ; then
		echo "mandrake"
		return 0
	fi

	if [ -f "/etc/redhat-release" ] ; then
		echo "redhat" #and centos
		return 0
	fi

	if [ -f "/etc/SuSE-release" ] ; then
		echo "suse"
		return 0
	fi
	
	echo "unknown"		
	return 1
}


# Prints 
detect_os_version()
{
	local osname=$1 ver=""
	case "$osname" in
		debian)
			echo ""
		;;
		redhat|fedora)
			ver=`rpm -qf /etc/redhat-release | sed -e "s/[-a-zA-Z]*-\([0-9]\+\).*/\1/g"`
			echo $ver
		;;
		mandrake)
			ver=`cat /etc/mandrake-release | cut -d' ' -f4`
			echo $ver
		;;
		unknown|*)
			echo ""
		;;
	esac

	return 0
}


# Returns:
# 0 - precompiled kernel modules are available for kernel version $1 on arch $2
# 1 - otherwise
check_precomp_kmods()
{
	if [ $(echo $1 | cut -d'.' -f2) -eq 4 ]; then
		# 2.4.x
		kext=o
	else
		# 2.6.x
		kext=ko
	fi

	# TODO
	# Rework this stupid code.

	[ -d "$KMOD_DIR" ] || return 1
	kdir=$(ls "$KMOD_DIR" 2>/dev/null | grep "${1}-${2}")
	[ -n "$kdir" ] || return 1
	for kmod_path in $KMODS_PATHS; do
		kmod=$(echo "$kmod_path" | sed -e "s#/.*##")
		fmod="${KMOD_DIR}/${kdir}/${kmod}.${kext}"
		[ -e "$fmod" ] || return 1
	done

	return 0
}


# Returns:
# 0 - 32-bit libc6 available
# 1 - otherwise
check_libc32()
{
	LANG=C file -L `ldconfig -p |
		grep '/libc\.so' |
		sed -e 's/^.* => //'` 2>/dev/null |
		grep -q 'ELF 32-bit' && return 0

	return 1
}


# Checks if libasound.so.2 is installed in system
# Argument:
#  32 or 64 - requested bitness of libasound
# Returns:
# 0 - libasound.so.2 is installed
# 1 - otherwise
check_alsa()
{
	LANG=C file -L `ldconfig -p |
		grep '/libasound\.so\.2' |
		sed -e 's/^.* => //'` 2>/dev/null |
		grep -q "ELF ${1}-bit" && return 0

	return 1
}


# Prints out list of packages needed to install to resolve dependences
# of libraries listed in $lib_deps_file.
# All packages are marked as mandatory.
process_lib_deps_file()
{
	test  -r "$lib_deps_file" || \
		(perror "Cannot read lib deps file '${lib_deps_file}'"; exit 1)

	local dep_libs_list=''
	IFS=$'\n'
	for elf_file in `cat "$lib_deps_file"`
	do
		if ! ldd "$elf_file" >/dev/null 2>&1; then
			# file is not an valid executalbe for this system, just skip it
			continue
		fi
		deps=`LANG=C ldd "$elf_file" | grep 'not found' | awk '{print $1}'`
		dep_libs_list="${dep_libs_list:+${dep_libs_list}${IFS}}${deps}"
	done
	unset IFS
	dep_libs_list=`echo "$dep_libs_list" | sort -u`

	# all dependencies are met
	test -z "$dep_libs_list" && return

	# need to get list of packages to resolve all that deps
	mapped_dep_libs_list=`echo "$dep_libs_list" |
		while read libname; do
			mapped_libname=$(map_libpackage_name ${libname})
			test $? -eq 0 && echo "m ${mapped_libname}" || echo "m ${libname}"
		done`
	echo "$mapped_dep_libs_list" | sort -u
}


# Returns list of packages needed for product $1 on distro $2 of version $3
check_deps()
{
	local deps_list=''

	if echo "server workstation pmc c2v" | grep -q "$1"; then
		check_libc32 ||
			deps_list="${deps_list:+${deps_list}\n}m libc32"
	fi

	echo "server workstation gtools transporter" | grep -q "$1"
	if [ $? -eq 0 ]; then
		# product uses kernel modules

		local kver=$(uname -r)

		install_need='m'
		if check_precomp_kmods $kver $karch; then
			# Install packages optionally
			install_need='o'
		fi
		
		type gcc > /dev/null 2>&1 ||
			deps_list="${deps_list:+${deps_list}\n}$install_need gcc"

		type make > /dev/null 2>&1 ||
			deps_list="${deps_list:+${deps_list}\n}$install_need make"

		test -f "/lib/modules/${kver}/build/include/linux/version.h" ||
			deps_list="${deps_list:+${deps_list}\n}$install_need kheaders"

		type perl > /dev/null 2>&1 ||
			deps_list="${deps_list:+${deps_list}\n}$install_need perl"
			
		type dkms > /dev/null 2>&1 ||
			deps_list="${deps_list:+${deps_list}\n}o dkms"
	fi

	if [ "x$1" = "xworkstation" ]; then
		if ! check_alsa 32; then
			deps_list="${deps_list:+${deps_list}\n}m alsa32"
		fi
		if [ "_$karch" = "_x86_64" ]  && ! check_alsa 64; then
			deps_list="${deps_list:+${deps_list}\n}m alsa64"
		fi
	fi

	if [ "x$1" = "xc2v" ]; then
		type nbd-client > /dev/null 2>&1 ||
			deps_list="${deps_list:+${deps_list}\n}m nbd"
	fi

	echo -e "$deps_list"
	return 0
}


# Prints list of packages needed for installation
# in such form:
# >m package_name0
# >m package_name2
# >...
# >o package_nameX
# >o package_nameX+1
#
# Here the first letter is 'status' of the package:
# m - mandatory
# o - optional
# - they are processed differently
check_packages()
{
	local os_name=`detect_os_name`
	local os_version=`detect_os_version $os_name`
	local deps_list=`check_deps $target_product $os_name $os_version`

	# if lib-deps option was specified - process deps from appropriate file
	test -n "$lib_deps_file" && \
		process_lib_deps_file

	# If list is empty - dont print anything to keep output clear
	test -z "$deps_list" && return

	local deps_list_mapped=`echo "$deps_list" |
	while read package_state package_name; do
		echo "${package_state} $(map_package_name \
			${package_name} ${os_name} ${os_version})"
	done`
	echo "$deps_list_mapped" | sort
}


# Returns list of packages (generic names) required by guest tools 
get_gtools_deps()
{
	local os_name=`detect_os_name`
	local os_version=`detect_os_version $os_name`
	check_deps gtools $os_name $os_version
}


pm_parse_cmdline $@


case $action in
	check)
		deps_list=`check_packages`
		
		test -z "$deps_list" && exit $PM_OK

		# There are some packages to install
		pm=`package_manager`
		# Show them, and place mandatory packages first
		echo "$deps_list"
		test -z $pm && exit $PM_NOT_FOUND
		exit $PM_OK
	;;

	install)
		pm=`package_manager`
		test -z $pm && exit $PM_NOT_FOUND

		deps_list=`check_packages`
		# Suppose here that package names dont have spaces in their names
		mnd_deps_list=`echo "$deps_list" | grep '^m' | cut -d' ' -f2`
		opt_deps_list=`echo "$deps_list" | grep '^o' | cut -d' ' -f2`

		# Processing mandatory packages
		# Inability to install some of them is fatal for the installation process
		if [ -n "$mnd_deps_list" ]; then
			# There are some mandatory packages to install
			mnd_deps_list=`echo "$mnd_deps_list" | tr '\n' ' '`
			pm_install $pm "$mnd_deps_list" "$logfile"
			rc=$?

			test $rc -eq $PM_LOCKED && exit $PM_LOCKED
			if [ $rc -ne $PM_OK ]; then
				check_packages
				exit $PM_FAILED
			fi
		fi

		# Processing optional packages
		# If we are failed to install some of them - not fatal
		if [ -n "$opt_deps_list" ]; then
			# There are some optional packets to install
			opt_deps_list=`echo "$opt_deps_list" | tr '\n' ' '`
			pm_install $pm "$opt_deps_list" "$logfile"
			rc=$?

			test $rc -eq $PM_LOCKED && exit $PM_LOCKED
			if [ $rc -ne $PM_OK ]; then
				# Error in optional packets installation is not fatal
				check_packages
				exit $PM_OK
			fi
		fi

		exit $PM_OK
	;;

	check_old)
		deps_list=`get_gtools_deps`
		if [ -n "$FLAG_CHECK_ASK" ]; then
			test -z "$deps_list" && exit 0
			exit 1
		else
		# for unattended installation
			retcode=0
			echo $deps_list | grep -q gcc && let "retcode |= 1"
			echo $deps_list | grep -q make && let "retcode |= 2"
			echo $deps_list | grep -q kheaders && let "retcode |= 4"
			exit $retcode
		fi
	;;

	download_old)
		# Current version of guest tools installer supports only
		# 3 mandatory packages: gcc, make and kheaders
		deps_list=`check_packages`
		deps_list_mandatory=`echo "$deps_list" | grep '^m' | cut -d' ' -f2`
		deps_list=`echo "$deps_list" | cut -d' ' -f2`

		pm=`package_manager`
		if [ -z "$pm" ]; then
			[ -n "$deps_list_mandatory" ] && exit $PM_NOT_FOUND
			# only optional packages required
			exit 0
		fi

		if [ -n "$deps_list" ]; then
			deps_list=`echo "$deps_list" | tr '\n' ' '`
			pm_install $pm "$deps_list" "$logfile"
			rc=$?

			test $rc -eq $PM_LOCKED && exit 123
			if [ $rc -ne $PM_OK ]; then
				notinstalled_deps=`get_gtools_deps`
				retcode=0
				echo $notinstalled_deps | grep -q gcc && let "retcode |= 1"
				echo $notinstalled_deps | grep -q make && let "retcode |= 2"
				echo $notinstalled_deps | grep -q kheaders && let "retcode |= 4"
				exit $retcode
			fi
		fi

		exit 0
	;;

	*)
		perror "Unknown action"
	;;
esac

