#!/bin/sh
####################################################################################################
# @file detect-xserver.sh
#
# Detect Xorg version and modules directory
#
# @author ksenks@
# @author owner is anatolykh@
#
# Copyright (c) 2005-2010 Parallels Holdings, Ltd. and its affiliates
# All rights reserved.
# http://www.parallels.com
####################################################################################################

PATH=${PATH:+$PATH:}/sbin:/bin:/usr/sbin:/usr/bin:/usr/X11R6/bin

ARCH=$(uname -m)

E_NOERR=0
E_NOPARAM=150
E_NOXSERV=163
E_NOXMODIR=164

####################################################################################################
# Definition of X.Org server configuration directories
####################################################################################################

# Note that this variable is used for 64-bit Debian-based systems as well.
XORG_MODULES_DIRS32="/usr/lib/xorg/modules      \
                     /usr/lib/X11/modules       \
                     /usr/X11R6/lib/modules"

XORG_MODULES_DIRS64="/usr/lib64/xorg/modules    \
                     /usr/lib64/X11/modules     \
                     /usr/X11R6/lib64/modules"


####################################################################################################
# Show error
####################################################################################################

perror() {
	echo $1 1>&2
}

####################################################################################################
# Detection of Xorg version
####################################################################################################
get_x_server_version() {
	xver=
	if type Xorg > /dev/null 2>&1; then
		# Get version of X.Org server
		xver=$(Xorg -version 2>&1 | grep -i "x.org x server" | awk '{ print $4 }' | awk -F . '{ printf "%s.%s.%s", $1, $2, $3 }')
		if [ -z "$xver" ]; then
			xver=$(Xorg -version 2>&1 | grep -i "x window system version" | awk '{ print $5 }' | awk -F . '{ printf "%s.%s.%s", $1, $2, $3 }')
			if [ -z "$xver" ]; then
				xver=$(Xorg -version 2>&1 | grep -i "x protocol version" | awk '{ print $8 }' | awk -F . '{ printf "%s.%s", $1, $2 }')
			fi
		fi
	else
		perror "Error: XFree86 server is not supported now"
	fi

	if [ -z "$xver" ]; then
		perror "Error: could not determine X server version"
		exit $E_NOXSERV
	fi

	# Check... is it RC version of X server
	if [ "$(echo $xver | awk -F . '{ printf "x%s", $3 }')" != "x99" ]; then
		xver="$(echo $xver | awk -F . '{ printf "%s.%s", $1, $2 }')"
	fi
	
	echo "$xver"
	exit $E_NOERR
}

####################################################################################################
# Detection of Xorg modules directories
####################################################################################################
get_xmodules_dir() {
	xdirs=
	if [ "$ARCH" = "x86_64" ]; then
		# For 64-bit Debian-based systems 64-bit stuff is placed in /lib and
		# /usr/lib. So need to go through _DIRS32 as well.
		# It should be noted that if the system was updated from 32-bit one
		# this code may not work correctly. But it's not clear how it should
		# work in this case.
		xdirs="$XORG_MODULES_DIRS64 $XORG_MODULES_DIRS32"
	else
		xdirs="$XORG_MODULES_DIRS32"
	fi
	for xdir in $xdirs; do
		if [ -d "$xdir" ]; then
			echo "$xdir"
			exit $E_NOERR
		fi
	done

	perror "Error: could not find system directory with X modules"
	exit $E_NOXMODIR
}

case "$1" in
	-v | --xver)
		get_x_server_version
		;;
	-d | --xdir)
		get_xmodules_dir
		;;
	*)
		perror "Error: not enough parameteres"
		exit $E_NOPARAM
esac

