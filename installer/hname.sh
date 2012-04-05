#!/bin/bash


detect_os()
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

detect_version()
{
	local osname=$1 ver=""
	case "$osname" in
		debian)
			#it looks like in all debian/ubuntu package name is "linux-headers"
			#it does not matter os version
			echo ""
		;;
		redhat|fedora)
			ver=`rpm -qf /etc/redhat-release | sed -e "s/.*release-\([0-9]*\)-.*/\1/g"`
			echo $ver
		;;
		mandrake)
			ver=`cat /etc/madrake-release | cut -d' ' -f4`
			echo $ver
		;;
		unknown|*)
			echo ""
		;;
	esac

	return 0
}


header_name()
{	
	local osname=$1 ver=$2

	case "$osname" in
		debian)
			#it has no matter what debian version
			echo "linux-headers"
		;;
		redhat)
			#redhat/centos <= 3 headers included
			#in 'kernel' package
			echo "kernel-devel"
		;;
		fedora)
			#for old fedora OSs( fedora-core < 4 )
			#kernel header are included in 'kernel' package
			echo "kernel-devel"
		;;
		mandrake)
			# for 2008.0 & 2008.1 - kernel-devel
			# for older and newer - need to investigate
			echo "kernel-devel"
		;;
		suse)
			echo "kernel-source"
		;;
		unknown|*)
			echo "kernel-devel"
		;;
	esac

	return 0
}


osversion()
{
	os=`detect_os`
	if [ $? -ne 0 ] ; then
		echo "unknown distribution"
		exit 1
	fi

	version=`detect_version $os`
	if [ $? -ne 0 ] ; then
		echo "unknown version"
		exit 1
	fi

	echo $os $version
}


case $1 in
	osversion)
		osversion
		exit $?
		;;
	hname)
		os_version=$(osversion)
		header_name $os_version
		exit $?
		;;
	*)
		echo "Unknown argument"
		echo "Usage: $0 {osversion|hname}"
		exit 1
		;;
esac

