#!/bin/bash
#
# asl-build-install
# v1.0	WA3WCO	2023/09/07

title="AllStarLink Build and Install"

DO_SETUP="<--"
DO_PREPARE=""
DO_DAHDI=""
DO_ASTERISK=""
DO_ALLSTAR=""
DO_NODES_DIFF=""
DO_FINISH=""

MANAGE_KERNEL_HOLD=0
SKIP_REBOOT_CHECK=0

MSGBOX_HEIGHT=16
MSGBOX_WIDTH=60

MANY_SPACES="                              "

/usr/bin/clear

# check if root
SUDO=""
if [ $EUID != 0 ]; then
    SUDO="sudo"
    SUDO_EUID=$(${SUDO} id -u)
    if [ ${SUDO_EUID} -ne 0 ]; then
	whiptail --msgbox "This script must be run as root or with sudo" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi
fi

LOGIN_USER=$(who am i | awk '{print $1}')
if [ -z "${LOGIN_USER}" ]; then
    LOGIN_USER=$(who --short | awk '{print $1}')
fi

INSTALL_EXTRA_PACKAGES=${INSTALL_EXTRA_PACKAGES:-"NO"}
if [ "$INSTALL_EXTRA_PACKAGES" != "YES" ]; then
    case "${LOGIN_USER}" in
	# always install the extra packagse for the following login(s)
	"wa3wco" )
	    INSTALL_EXTRA_PACKAGES=YES
	    ;;
    esac
fi

DESTDIR=""
#DESTDIR="/tmp/asl-install-root"
if [ "${DESTDIR}" != "" ]; then
    ${SUDO} mkdir -p "${DESTDIR}"
fi

ASTERISK_D="${DESTDIR}/etc/asterisk"
ALLMON_D="${DESTDIR}/etc/allmon3"
ALLSCAN_D="${DESTDIR}/var/www/html/allscan"
SUPERMON_D="${DESTDIR}/var/www/html/supermon"

calc_wt_size()
{
    # Bash knows the terminal size
    #   The number of columns are $COLUMNS
    #   The number of lines are $LINES

    if [ $LINES -lt 22 ]; then
	echo "Terminal size must be at least 22 lines."
	exit
    fi
    if [ $COLUMNS -lt 60 ]; then
	echo "Terminal size must be at least 60 columns."
	exit
    fi

    WT_HEIGHT=22

    # Leave full width up to 100 columns
    WT_WIDTH=$COLUMNS
    if [ $COLUMNS -gt 100 ]; then
	WT_WIDTH=100
    fi

    WT_MENU_HEIGHT=$(($WT_HEIGHT - 8))
}

check_kernel_can_hold()
{
    # check if "dpkg-query" and "apt-mark" are available
    if ! [[ -x /usr/bin/dpkg-query && -x /usr/bin/apt-mark ]]; then
	# if kernel updates can not be held
	return 0
    fi

    return 1
}

check_kernel_has_holds()
{
    ARCH=$(dpkg --print-architecture)

    HELD=$(dpkg-query							\
	       --showformat='${db:Status-Abbrev};${binary:Package}\n'	\
	       --show							\
	       "linux-image-$ARCH"					\
	       "linux-headers-$ARCH"					\
	       "linux-image-*-$ARCH"					\
	       "linux-headers-*-$ARCH"					\
	   | grep -e "^hi..*linux.*"					\
	   | wc -l							\
	  )
    return $HELD
}

#
# manage_kernel_updates ( hold | unhold | showhold )
#
manage_kernel_updates()
{
    ACTION=$1
    ARCH=$(dpkg --print-architecture)

    case $ACTION in
	"hold" )
	    # put a "hold" on the newest kernel version
	    VERS="$(ls -1 /boot/vmlinuz* 2>/dev/null | sort -V | tail -1)"
	    VERS="${VERS#/boot/vmlinuz-}"
	    VERS="${VERS%-$ARCH}"
	    ;;
	* )
	    VERS="*"
	    ;;
    esac

    dpkg-query							\
	--showformat='${db:Status-Abbrev};${binary:Package}\n'	\
	--show							\
	"linux-image-$ARCH"					\
	"linux-headers-$ARCH"					\
	"linux-image-$VERS-$ARCH"				\
	"linux-headers-$VERS-$ARCH"				\
    | grep -e linux						\
    | while read package_info
    do
	re=^.i..*$
	if [[ $package_info =~ $re ]]; then
	    # if installed
	    package="${package_info#*;}"
	    ${SUDO} apt-mark $ACTION $package
	    RC=$?
	    if [[ $RC -ne 0 ]]; then
		echo "\"${SUDO} apt-mark $ACTION $package\" failed: RC=$RC"
		return $RC
	    fi
	fi
    done
}

allow_kernel_updates()
{
    check_kernel_can_hold
    if [[ $? -eq 0 ]]; then
	# if kernel updates can not be held
	return
    fi

    check_kernel_has_holds
    if [[ $? -eq 0 ]]; then
	# if kernel updates NOT blocked
	return
    fi

    if [[ $MANAGE_KERNEL_HOLD -eq 0 ]]; then
	MSG="Updates to the system kernel appear to have been blocked.  You can"
	MSG="${MSG} allow the kernel to be updated as long as the DAHDH kernel"
	MSG="${MSG} module is rebuilt after any changes."
	MSG="${MSG}\n\nNote: you will be prompted to reboot your system if a"
	MSG="${MSG} new kernel has been installed."
	MSG="${MSG}\n\nDo you want to allow the kernel to be updated now?"
	whiptail				\
	    --title "$title"			\
	    --yesno				\
	    "${MSG}"				\
	    ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	ANSWER=$?
	if [ ${ANSWER} -eq 0 ]; then
	    MANAGE_KERNEL_HOLD=1
	fi
    else
	ANSWER=0
    fi

    if [ ${ANSWER} -eq 0 ]; then
	manage_kernel_updates unhold
    fi
}

block_kernel_updates()
{
    check_kernel_can_hold
    if [[ $? -eq 0 ]]; then
	# if kernel updates can not be held
	return
    fi

    if [[ $MANAGE_KERNEL_HOLD -eq 0 ]]; then
	MSG="Future updates to the OS kernel can result in issues with the"
	MSG="${MSG} Asterisk software. This is due to a mismatch between the"
	MSG="${MSG} source code used to build/compile the DAHDI kernel module"
	MSG="${MSG} and the running version of the kernel."
	MSG="${MSG}\n\nDo you want to block future updates of the OS kernel?"
	whiptail				\
	    --title "$title"			\
	    --yesno				\
	    "${MSG}"				\
	    ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	ANSWER=$?
	if [ ${ANSWER} -eq 0 ]; then
	    MANAGE_KERNEL_HOLD=1
	fi
    else
	ANSWER=0
    fi

    if [[ $MANAGE_KERNEL_HOLD -ne 0 ]]; then
	manage_kernel_updates hold
    fi
}

do_welcome()
{
    calc_wt_size
    MSG="This command will walk you through the process of building and "
    MSG="${MSG}installing the software needed to run an AllStarLink node. "
    MSG="${MSG}You will be asked a number of questions. "
    MSG="${MSG}You may run this command as many times as you like."
    MSG="${MSG}\n\nWould you like to build/install the software now?"
    whiptail			\
	--title "$title"	\
	--yesno			\
	"${MSG}"		\
	${WT_HEIGHT} ${WT_WIDTH}
    ANSWER=$?
    if [ "${ANSWER}" = "0" ]; then
	return
    fi
    exit 0
}

add_update_packages()
{
    echo ""
    echo "Capture the most recent [linux] packages"
    echo ""
    #
    # Ensure that the various pieces are all in place
    # in order to build/install AllStarLink
    #
    if [ -x /usr/bin/yum ]; then
	${SUDO} yum update -y

	${SUDO} yum install -y		\
			alsa-lib-devel	\
			automake	\
			cronie		\
			gcc		\
			git		\
			httpd		\
			jansson-devel	\
			kernel-devel	\
			libcurl-devel	\
			libtool		\
			libusb-devel	\
			make		\
			ncurses-devel	\
			openssl-devel	\
			patchutils	\
			php		\

	if [ "${INSTALL_EXTRA_PACKAGES}" = "YES" ]; then
	    ${SUDO} yum install -y avahi-daemon lsof mlocate
	fi

	${SUDO} yum autoremove
    elif [ -x /usr/bin/apt ]; then
	allow_kernel_updates

	${SUDO} apt update

	${SUDO} apt upgrade -y

	${SUDO} apt install -y		\
		apache2			\
		autoconf		\
		automake		\
		build-essential		\
		cmake			\
		curl			\
		git			\
		libapache2-mod-php	\
		libasound2-dev		\
		libcurl4-openssl-dev	\
		libi2c-dev		\
		libjansson-dev		\
		libncurses-dev		\
		libnewt-dev		\
		libspeex-dev		\
		libssl-dev		\
		libtonezone-dev		\
		libtool			\
		libusb-1.0-0-dev	\
		libusb-dev		\
		linux-headers-`uname -r`\
		pandoc			\
		php			\
		php-sqlite3		\
		pkg-config		\
		python3-aiohttp		\
		python3-aiohttp-session	\
		python3-argon2		\
		python3-websockets	\
		rsync			\
		zip			\

	if [ "${INSTALL_EXTRA_PACKAGES}" = "YES" ]; then
	    ${SUDO} apt install -y apt-file avahi-daemon lsof mlocate
	fi

	${SUDO} apt autoremove -y

	block_kernel_updates
    else
	echo "Unsupported OS"
	exit 1
    fi

    if [ "${INSTALL_EXTRA_PACKAGES}" = "YES" ]; then
	#
	# apt-file
	#
	if [ -x /usr/bin/apt-file ]; then
	    ${SUDO} apt-file update
	fi

	#
	# avahi
	#
	SERVICE=ssh.service
	AVAHI_EXAMPLES=/usr/share/doc/avahi-daemon/examples
	AVAHI_SERVICES=/etc/avahi/services
	if [ -f "${AVAHI_EXAMPLES}/${SERVICE}" -a ! -f "${AVAHI_SERVICES}/${SERVICE}" ]; then
	    ${SUDO} cp "${AVAHI_EXAMPLES}/${SERVICE}" "${AVAHI_SERVICES}/${SERVICE}"
	fi

	#
	# [m]locate
	#
	if [ -x /usr/bin/updatedb ]; then
	    ${SUDO} updatedb
	fi

	#
	# ex/vi[m] configuration
	#
	if [ ! -f ~/.exrc ]; then
		cat <<_END_OF_INPUT > ~/.exrc
:set ignorecase
:set showmatch
:set ts=8
_END_OF_INPUT
	fi
    fi
}

add_update_source()
{
    url="${1}"

    r=$(basename ${url})
    d=$(basename ${r} .git)

    if [ -d ${d} ]; then
	CUR_REPO=$(cd "${d}"; git config --get remote.origin.url)
	if [ "${CUR_REPO}" != "${url}" ]; then
	    echo "* Current \"${d}\" git repository url changed, removing \"old\" repo"
	    echo ""
	    rm -rf "${d}"
	fi
    fi

    if [ ! -d "${d}" ]; then
	echo "* Fetching \"${d}\""
	echo ""
	git clone "${url}"
	echo ""
    else
	echo "* Updating \"${d}\" (preserving any changes)"
	echo ""
	(cd "${d}"					\
	;git stash					\
	;git pull --rebase				\
	;git stash pop					\
	)
	echo ""
    fi
}

fetch_update_source()
{
    echo ""
    echo "Capture the most recent [AllStarLink] packages"
    echo ""
    #
    # Add component projects
    #
    for url in							\
	"https://github.com/Allan-N/ASL-DAHDI.git"		\
	"https://github.com/Allan-N/ASL-Asterisk.git"		\
	"https://github.com/AllStarLink/ASL-Nodes-Diff.git"	\

    do
	add_update_source "${url}"
    done
}

add_asterisk_user()
{
    #
    # add "asterisk" user
    #   (from ./ASL-Asterisk/asterisk/debian/asl-asterisk.postinst)
    #
    getent passwd asterisk	> /dev/null
    if [ $? -eq 2 ]; then
	echo ""
	echo "Adding system user for Asterisk"
	echo ""
	if [ -x /usr/sbin/useradd ]; then
	    ${SUDO} useradd				\
			--comment "Asterisk PBX daemon"	\
			--home-dir /var/lib/asterisk	\
			--groups audio,dialout		\
			--no-create-home		\
			--system			\
			--user-group			\
			asterisk
	else
	    ${SUDO} adduser				\
			--system			\
			--group				\
			--quiet				\
			--home /var/lib/asterisk	\
			--no-create-home		\
			--disabled-login		\
			--gecos "Asterisk PBX daemon"	\
			asterisk

	    for group in audio dialout
	    do
		${SUDO} adduser asterisk $group
	    done
	fi
    fi
}

check_www()
{
    for WWW_GROUP in "www-data" "http" "apache"
    do
	if [ `grep "^${WWW_GROUP}:" /etc/group` ]; then
	    return 0
	fi
    done

    whiptail --msgbox "Web server not installed, please run setup" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
    return 1
}

add_apache_permissions()
{
    check_www
    if [ $? -ne 0 ]; then
	return
    fi

    echo ""
    echo "Update web server permissions"
    echo ""

    # add a default web page
    if [ ! -f "${DESTDIR}/var/www/html/index.html" ]; then
	if [ -f "/usr/share/httpd/noindex/index.html" ]; then
	    ${SUDO} cp "/usr/share/httpd/noindex/index.html" "${DESTDIR}/var/www/html/index.html"
	fi
    fi

    # update [current] user groups and document root permissions
    if [ -x /usr/sbin/usermod ]; then	
	${SUDO} usermod				\
		--append			\
		--groups ${WWW_GROUP}		\
		${LOGIN_USER}
    else
	${SUDO} adduser ${LOGIN_USER} ${WWW_GROUP}
    fi
}

do_setup()
{
    add_update_packages
    fetch_update_source
    add_asterisk_user
    add_apache_permissions

    DO_SETUP="OK"
    DO_PREPARE="<--"
}

check_setup()
{
    if [ -d ASL-DAHDI ] && [ -d ASL-Asterisk ] && [ -d ASL-Nodes-Diff ] ; then
	return 0
    fi

    # it looks like we are trying to skip steps so restart UI guidance
    DO_SETUP="<--"
    DO_PREPARE=""
    DO_DAHDI=""
    DO_ASTERISK=""
    DO_ALLSTAR=""
    DO_NODES_DIFF=""
    DO_FINISH=""

    # and advise (complain) :-)
    whiptail --msgbox "AllStarLink components are missing.  Please run the \"Setup\" step." ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
    return 1
}

do_prepare()
{
    echo "CLEAN the [AllStarLink] packages"

    check_setup
    if [ $? -ne 0 ]; then
	return
    fi

    echo "* DAHDI"									| tee /var/tmp/clean-dahdi.txt
    make -C ASL-DAHDI distclean								>> /var/tmp/clean-dahdi.txt	2>&1
#   if [ $? -ne 0 ]; then
#	whiptail --msgbox "ASL-DAHDI clean failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
#	exit 1
#   fi

    echo "* Asterisk"									| tee /var/tmp/clean-asterisk.txt
    make -C ASL-Asterisk/asterisk distclean						>> /var/tmp/clean-asterisk.txt	2>&1
#   if [ $? -ne 0 ]; then
#	whiptail --msgbox "ASL-Asterisk clean failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
#	exit 1
#   fi

    if [ "$DO_SETUP" = "<--" ]; then
	DO_SETUP=""
    fi
    DO_PREPARE="OK"
    DO_DAHDI="<--"
}

do_dahdi()
{
    echo "Build/install DAHDI"								| tee /var/tmp/build-dahdi.txt

    check_setup
    if [ $? -ne 0 ]; then
	return
    fi

    #
    # we need to add a kernel module signing cert to build DAHDI
    # on Amazon Linux [2023]
    #
    if [ -f /etc/amazon-linux-release ]; then
	CERTS_DIR="/usr/src/kernels/$(uname -r)/certs"
	if [ -d "${CERTS_DIR}"				\
	     -a ! -f "${CERTS_DIR}/signing_key.x509"	\
	     -a ! -f "${CERTS_DIR}/signing_key.pem" ]; then

	    echo "* add kernel module signing key"					| tee -a /var/tmp/build-dahdi.txt

	    X509_GENKEY=/tmp/x509.genkey

	    cat <<_END_OF_INPUT > "${X509_GENKEY}"
[ req ]
default_bits = 4096
distinguished_name = req_distinguished_name
prompt = no
string_mask = utf8only
x509_extensions = myexts

[ req_distinguished_name ]
CN = Modules

[ myexts ]
basicConstraints=critical,CA:FALSE
keyUsage=digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
_END_OF_INPUT

	    ${SUDO} openssl				\
		req					\
		-outform DER				\
		-out	"${CERTS_DIR}/signing_key.x509"	\
		-new					\
		-nodes					\
		-keyout	"${CERTS_DIR}/signing_key.pem"	\
		-sha512					\
		-config	"${X509_GENKEY}"		\
		-x509					\
		-days 36500				\
		-utf8					\
		-batch					\
		2> /dev/null

	    rm -f "${X509_GENKEY}"
	fi
    fi

    echo "* autoupdate (configure.ac)"							| tee -a /var/tmp/build-dahdi.txt
    (cd ASL-DAHDI/tools;		autoupdate)					>> /var/tmp/build-dahdi.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-DAHDI/tools autoupdate configure.ac failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-dahdi.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* autoupdate (acinclude.m4)"							| tee -a /var/tmp/build-dahdi.txt
    (cd ASL-DAHDI/tools;		autoupdate acinclude.m4)			>> /var/tmp/build-dahdi.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-DAHDI/tools autoupdate acinclude.m4 failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-dahdi.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* autoreconf"									| tee -a /var/tmp/build-dahdi.txt
    (cd ASL-DAHDI/tools;		autoreconf --install --force)			>> /var/tmp/build-dahdi.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-DAHDI/tools autoreconf failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-dahdi.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make"									| tee -a /var/tmp/build-dahdi.txt
    make -C ASL-DAHDI MODULES_EXTRA="dahdi_dummy"					>> /var/tmp/build-dahdi.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-DAHDI build failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-dahdi.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make install"								| tee -a /var/tmp/build-dahdi.txt
    ${SUDO} make -C ASL-DAHDI install MODULES_EXTRA="dahdi_dummy" DESTDIR="${DESTDIR}"	>> /var/tmp/build-dahdi.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-DAHDI install failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-dahdi.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make config"								| tee -a /var/tmp/build-dahdi.txt
    ${SUDO} make -C ASL-DAHDI config				DESTDIR="${DESTDIR}"	>> /var/tmp/build-dahdi.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-DAHDI config failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-dahdi.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make tools/install-config"							| tee -a /var/tmp/build-dahdi.txt
    HACK="/var/tmp/build-dahdi.txt-$$"
    ${SUDO} make -C ASL-DAHDI/tools install-config		DESTDIR="${DESTDIR}"	>  ${HACK}			2>&1
    STATUS=$?
    cat ${HACK}										>> /var/tmp/build-dahdi.txt
    rm -f ${HACK}
    if [ $STATUS -ne 0 ]; then
	MSG="ASL-DAHDI/tools install-config failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-dahdi.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    if [ -f "${DESTDIR}/etc/dahdi/system.conf.sample" -a ! -f "${DESTDIR}/etc/dahdi/system.conf" ]; then
	${SUDO} install						\
		-m 644						\
		"${DESTDIR}/etc/dahdi/system.conf.sample"	\
		"${DESTDIR}/etc/dahdi/system.conf"
    fi

    ${SUDO} chown -R asterisk:asterisk	"${DESTDIR}/dev/dahdi"
    ${SUDO} chmod -R u=rwX,g=rX,o=	"${DESTDIR}/dev/dahdi"

    if [ "$DO_SETUP" = "<--" ]; then
	DO_SETUP=""
    fi
    if [ "$DO_PREPARE" = "<--" ]; then
	DO_PREPARE=""
    fi
    DO_DAHDI="OK"
    DO_ASTERISK="<--"
}

do_asterisk()
{
    check_setup
    if [ $? -ne 0 ]; then
	return
    fi

    if [ ! -f /usr/include/dahdi/tonezone.h -o ! -f /etc/modprobe.d/dahdi.conf ]; then
	whiptail --msgbox "DAHDI not built/installed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "Build/install Asterisk"							| tee /var/tmp/build-asterisk.txt

    echo "* autoupdate (asterisk/configure.ac)"						| tee -a /var/tmp/build-asterisk.txt
    (cd ASL-Asterisk/asterisk;			autoupdate)				>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-Asterisk/asterisk autoreconf failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-asterisk.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* autoupdate (asterisk/menuselect/configure.ac)"				| tee -a /var/tmp/build-asterisk.txt
    (cd ASL-Asterisk/asterisk/menuselect;	autoupdate)				>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-Asterisk/asterisk/menuselect autoreconf configure.ac failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-asterisk.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* autoupdate (asterisk/menuselect/acinclude.m4)"				| tee -a /var/tmp/build-asterisk.txt
    (cd ASL-Asterisk/asterisk/menuselect;	autoupdate acinclude.m4)		>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-Asterisk/asterisk/menuselect autoreconf acinclude.m4 failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-asterisk.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* autoupdate (asterisk/autoconf/*.m4)"					| tee -a /var/tmp/build-asterisk.txt
    (cd ASL-Asterisk/asterisk/autoconf;		autoupdate *.m4)			>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-Asterisk/asterisk/autoconf autoreconf *.m4 failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-asterisk.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* autoreconf (asterisk)"							| tee -a /var/tmp/build-asterisk.txt
    (cd ASL-Asterisk/asterisk;			autoreconf --install --force)		>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-Asterisk/asterisk autoreconf failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-asterisk.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* configure"									| tee -a /var/tmp/build-asterisk.txt
    (cd ASL-Asterisk/asterisk;			./configure)				>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-Asterisk/asterisk configure failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-asterisk.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make		(Note: this may take a while)"				| tee -a /var/tmp/build-asterisk.txt
    make -C ASL-Asterisk/asterisk							>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-Asterisk/asterisk build failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-asterisk.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make install"								| tee -a /var/tmp/build-asterisk.txt
    ${SUDO} make -C ASL-Asterisk/asterisk install		DESTDIR="${DESTDIR}"	>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-Asterisk/asterisk install failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-asterisk.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make config"								| tee -a /var/tmp/build-asterisk.txt
    ${SUDO} make -C ASL-Asterisk/asterisk config		DESTDIR="${DESTDIR}"	>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-Asterisk/asterisk config failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-asterisk.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make samples"								| tee -a /var/tmp/build-asterisk.txt
    ${SUDO} make -C ASL-Asterisk/asterisk samples OVERWRITE="n"	DESTDIR="${DESTDIR}"	>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	MSG="ASL-Asterisk/asterisk samples failed"
	MSG="${MSG}\n\nCheck \"/var/tmp/build-asterisk.txt\" for details."
	whiptail --msgbox "${MSG}" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    if [ -f ${DESTDIR}/etc/asterisk/modules.conf -a ! -f ASL-Asterisk/asterisk/codecs/codec_ilbc.o ]; then	\
	${SUDO} sed -i 's/\(^load .* codec_ilbc.so .*\)/no\1/'	${DESTDIR}/etc/asterisk/modules.conf;		\
    fi

    if [ -f /etc/debian_version ]; then
	(cd ASL-Asterisk/asterisk/debian;				\
	    ${SUDO} install						\
		-m 644							\
		snd_pcm_oss.conf					\
		${DESTDIR}/etc/modules-load.d/snd_pcm_oss.conf		\
	)
    fi

    ${SUDO} chown -R asterisk:asterisk	"${DESTDIR}/var/lib/asterisk"
    ${SUDO} chmod -R u=rwX,g=rX,o=	"${DESTDIR}/var/lib/asterisk"

    ${SUDO} chown -R asterisk:asterisk	"${DESTDIR}/var/log/asterisk"
    ${SUDO} chmod -R u=rwX,g=rX,o=	"${DESTDIR}/var/log/asterisk"

    ${SUDO} chown -R asterisk:asterisk	"${DESTDIR}/var/run/asterisk"
    ${SUDO} chmod -R u=rwX,g=rX,o=	"${DESTDIR}/var/run/asterisk"

    ${SUDO} chown -R asterisk:asterisk	"${DESTDIR}/var/spool/asterisk"
    ${SUDO} chmod -R u=rwX,g=rX,o=	"${DESTDIR}/var/spool/asterisk"

    ${SUDO} chown -R asterisk:asterisk	"${DESTDIR}/usr/lib/asterisk"
    ${SUDO} chmod -R u=rwX,g=rX,o=	"${DESTDIR}/usr/lib/asterisk"

    ${SUDO} chown -R root:asterisk	"${DESTDIR}/etc/asterisk"
    ${SUDO} chmod -R u=rwX,g=rX,o=	"${DESTDIR}/etc/asterisk"
    ${SUDO} chmod -R g+w		"${DESTDIR}/etc/asterisk/voicemail.conf"
#   ${SUDO} chmod -R g+w,+t		"${DESTDIR}/etc/asterisk"

    if [ "$DO_SETUP" = "<--" ]; then
	DO_SETUP=""
    fi
    if [ "$DO_PREPARE" = "<--" ]; then
	DO_PREPARE=""
    fi
    if [ "$DO_DAHDI" = "<--" ]; then
	DO_DAHDI="??"
    fi
    DO_ASTERISK="OK"
    DO_ALLSTAR="<--"
}

do_allstar()
{
    echo "Build/Install AllStar"							| tee /var/tmp/build-allstar.txt

    check_setup
    if [ $? -ne 0 ]; then
	return
    fi

    echo "* make install"								| tee -a /var/tmp/build-allstar.txt
    ${SUDO} make -C ASL-Asterisk/allstar install		DESTDIR="${DESTDIR}"	>> /var/tmp/build-allstar.txt	2>&1

    (cd ASL-Asterisk/allstar/debian;					\
	${SUDO} install							\
		-m 644							\
		allstar-helpers.cron.d					\
		${DESTDIR}/etc/cron.d/allstar-helpers			\
    )

    (cd ASL-Asterisk/allstar/debian;					\
	${SUDO} install							\
		-m 755							\
		allstar-helpers.cron.daily				\
		${DESTDIR}/etc/cron.daily/allstar-helpers		\
    )

    DO_ALLSTAR="OK"
    DO_NODES_DIFF="<--"
}

do_nodes_diff()
{
    echo "Build/install Nodes-Diff"							| tee /var/tmp/build-nodes-diff.txt

    check_setup
    if [ $? -ne 0 ]; then
	return
    fi

    (cd ASL-Nodes-Diff;							\
	${SUDO} install							\
		-m 755							\
		update-node-list.sh					\
		${DESTDIR}/usr/sbin/update-node-list.sh			\
    )

    ${SUDO} mkdir -p ${DESTDIR}/lib/systemd/system
    (cd ASL-Nodes-Diff;							\
	${SUDO} install							\
		-m 644							\
		update-node-list.service				\
		${DESTDIR}/lib/systemd/system/update-node-list.service;	\
	${SUDO} sed -i -e 's;/usr/local/sbin;/usr/sbin;'		\
		${DESTDIR}/lib/systemd/system/update-node-list.service;	\
    )
    if [ -z "${DESTDIR}" ]; then
	${SUDO} /bin/systemctl enable update-node-list.service
    fi

    DO_NODES_DIFF="OK"
    DO_FINISH="<--"
}

do_web_user()
{
    if [ -n "${WEBUSER_USER}" -a -n "${WEBUSER_PASS}" ]; then
	# if we already have a [web] user
	return
    fi

    WEBUSER_USER=""
    while [ "${WEBUSER_USER}" = "" ]; do
	WEBUSER_USER=$(whiptail									\
			   --title "$title"							\
			   --inputbox "Enter \"web\" login for Node ${CURRENT_NODE_D}"		\
			   ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
			   3>&1 1>&2 2>&3)
	if [ $? -ne 0 ]; then
	    return $?
	fi
    done

    WEBUSER_PASS="A"
    WEBUSER_PASS2="B"
    while [ "${WEBUSER_PASS}" != "${WEBUSER_PASS2}" ]; do
	WEBUSER_PASS=$(whiptail									\
			   --title "$title"							\
			   --passwordbox "Enter \"web\" password for login ${WEBUSER_USER}"	\
			   ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
			   3>&1 1>&2 2>&3)
	if [ $? -ne 0 ]; then
	    return $?
	fi

	WEBUSER_PASS2=$(whiptail								\
			    --title "$title"							\
			    --passwordbox "Verify \"web\" password for login ${WEBUSER_USER}"	\
			    ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
			    3>&1 1>&2 2>&3)
	if [ $? -ne 0 ]; then
	    return $?
	fi

       	if [ "${WEBUSER_PASS}" != "${WEBUSER_PASS2}" ]; then
	    whiptail --msgbox "Passwords must match" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	fi
    done

    return 0
}

do_allmon()
{
    echo "Build/install Allmon3"

    check_www
    if [ $? -ne 0 ]; then
	return
    fi

    add_update_source "https://github.com/AllStarLink/Allmon3.git"

    #
    # Update the version #'s
    #
    make -C Allmon3 verset

    #
    # ... and install from the latest/updated source
    #
    ${SUDO} make -C Allmon3 install	DESTDIR="${DESTDIR}"	>> /var/tmp/build-allmon3.txt	2>&1

    #
    # ... and revert the version # updates
    #
    (cd Allmon3;				\
     git restore $(git status			\
		   | grep -e 'modified:'	\
		   | sed -e 's/modified://'	\
		  )				\
    )

    #
    # ... and add a link that would have been dropped in by the debian package
    #
    ${SUDO} ln -f -s "${DESTDIR}${ALLMON_D}/custom.css" "${DESTDIR}/usr/share/allmon3/css/custom.css"

    #
    # configure
    #
    (cd Allmon3/debian;									\
	${SUDO} env DPKG_MAINTSCRIPT_NAME=postinst /bin/sh ./postinst configure 0.0.0	\
    )

    #
    # ... and add/enable the service
    #
    (cd Allmon3/debian;						\
	${SUDO} install						\
		-m 644						\
		allmon3.service					\
		${DESTDIR}/lib/systemd/system/allmon3.service	\
    )

    #
    # if needed, add [web] user
    #
    ALLMON_USER=$(${SUDO} grep -v -e "^user|" -e "^allmon3|" "${DESTDIR}${ALLMON_D}/users")
    if [ -z "${ALLMON_USER}" ]; then
	do_web_user
	if [ $? -ne 0 ]; then
	    return
	fi

	${SUDO} "${DESTDIR}/usr/bin/allmon3-passwd" ${WEBUSER_USER} <<_END_OF_INPUT
${WEBUSER_PASS}
${WEBUSER_PASS}
_END_OF_INPUT
    fi

    #
    # ... and, lastly, start the service
    #
    ${SUDO} /bin/systemctl enable allmon3
    ${SUDO} /bin/systemctl restart allmon3

    DO_ALLMON=""
}

do_supermon()
{
    echo "Build/install Supermon"

    check_www
    if [ $? -ne 0 ]; then
	return
    fi

    add_update_source "https://github.com/Allan-N/ASL-Supermon.git"

    (cd ASL-Supermon;							\
	tar --create --file - usr/local/sbin var/www/html		\
    ) |									\
    (cd "${DESTDIR}/";							\
	${SUDO} tar --extract --no-same-owner --file -			\
    )

    ${SUDO} sed -i				\
		-e '/^\[1998]/,/^$/ s/^/;/'	\
		-e 's/1998,//'			\
		-e 's/node=1998/node=1999/'	\
		"${DESTDIR}/var/www/html/supermon/allmon.ini"

    #
    # if needed, add [web] user
    #
    WEBUSER_PASSWD="${DESTDIR}/var/www/html/supermon/.htpasswd"
    if [ ! -f "${WEBUSER_PASSWD}" ]; then
	do_web_user
	if [ $? -ne 0 ]; then
	    return
	fi

	${SUDO} htpasswd -i -c -B "${WEBUSER_PASSWD}" ${WEBUSER_USER} <<_END_OF_INPUT
${WEBUSER_PASS}
_END_OF_INPUT
    fi

    #
    # if needed, add .htaccess
    #
    SUPERMON_ACCESS="${DESTDIR}/var/www/html/supermon/.htaccess"
    if [ ! -f "${SUPERMON_ACCESS}" ]; then
	cat <<_END_OF_INPUT | ${SUDO} tee "${SUPERMON_ACCESS}"		> /dev/null
<FilesMatch "\.(htaccess|htpasswd|ini|ini.php|log|sh|inc|bak|save)$">
Order Allow,Deny
Deny from all
</FilesMatch>
_END_OF_INPUT
    fi

    #
    # Update web server log file location
    #
    if [ ! -d "/var/log/apache2" -a -d "/var/log/httpd" ]; then
	${SUDO} sed -i -e 's;/var/log/apache2;/var/log/httpd;'	"${DESTDIR}/var/www/html/supermon/common.inc"
    fi

    #
    # update permissions
    #
    ${SUDO} chgrp ${WWW_GROUP}	"${DESTDIR}/var/www/html/supermon"
    ${SUDO} chmod g+rwX		"${DESTDIR}/var/www/html/supermon"
    ${SUDO} chgrp ${WWW_GROUP}	"${DESTDIR}/var/www/html/supermon/favorites.ini"
    ${SUDO} chmod g+rwX		"${DESTDIR}/var/www/html/supermon/favorites.ini"

    #
    # if needed, update sudoers
    #
    SUPERMON_SUDOERS="${DESTDIR}/etc/sudoers.d/supermon"
    if [ ! -f "${SUPERMON_SUDOERS}" ]; then
	cat <<_END_OF_INPUT | ${SUDO} tee "${SUPERMON_SUDOERS}"		> /dev/null
#
# Commands used by AllStarLink / Supermon
#
Cmnd_Alias SUPERMON =			\\
  /bin/killall,				\\
  /bin/reboot,				\\
  /bin/top,				\\
  /usr/bin/journalctl,			\\
  /usr/bin/rm,				\\
  /usr/bin/sync				\\
  /usr/local/sbin/astlookup,		\\
  /usr/local/sbin/astst,		\\
  /usr/local/sbin/irlplookup,		\\
  /usr/local/sbin/ssinfo,		\\
  /usr/local/sbin/supermon/echolookup,	\\
  /usr/sbin/astdn.sh,			\\
  /usr/sbin/asterisk,			\\
  /usr/sbin/astup.sh
User_Alias ADMINS = ${WWW_GROUP}
ADMINS ALL = NOPASSWD: SUPERMON
_END_OF_INPUT
    fi

    DO_SUPERMON=""
}

do_allscan()
{
    echo "Build/install AllScan"

    check_www
    if [ $? -ne 0 ]; then
	return
    fi

    add_update_source "https://github.com/davidgsd/AllScan.git"

    #
    # copy the latest/updated source files
    #
    (cd AllScan;	${SUDO} ./_tools/copyToWww.php)

    #
    # installed files should be root:root
    #
    ${SUDO} chown -R 0:0 "${DESTDIR}/var/www/html/allscan"

    #
    # and run the install script too!
    #
    (cd AllScan;	${SUDO} ./AllScanInstallUpdate.php)

    DO_ALLSCAN=""
}

do_configure_node()
{
    if [ ! -x /usr/sbin/node-setup ]; then
	return
    fi

    MSG="Set up hotspot/repeater, node number, and other AllStar settings."
    MSG="${MSG}\n\nWould you like to change the AllStar settings?"
    whiptail					\
	--title "$title"			\
	--yesno					\
	"${MSG}"				\
	${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
    ANSWER=$?
    if [ ${ANSWER} -eq 0 ]; then
	${SUDO} /usr/sbin/node-setup
    fi
}

read_asl_config()
{
#   echo "Read ASL configurtation files ${1}"

    NEED_CONFIG_NODE=0
    NEED_CONFIG_WEB=0
    NEED_NODE_WEB_SYNC=0

    CURRENT_NODE=$(${SUDO} grep -o '^\[[0-9]*\]' "${ASTERISK_D}/rpt.conf" 2>/dev/null				| \
		   sed 's/^.//;s/.$//')
    CURRENT_NODE_D="${CURRENT_NODE}"
    case "${CURRENT_NODE}" in
	"" | "1999" )
	    CURRENT_NODE_D="Not configured"
	    NEED_CONFIG_NODE=$(($NEED_CONFIG_NODE + 1))
	    ;;
    esac

    CURRENT_CALL=$(${SUDO} grep '^idrecording\s*=\s*' "${ASTERISK_D}/rpt.conf" 2>/dev/null			| \
		   sed 's/.*|i\([0-9a-zA-Z/-]*\).*/\1/')
    CURRENT_CALL_D="${CURRENT_CALL}"
    case "${CURRENT_CALL}" in
	"" | "WB6NIL" )
	    CURRENT_CALL_D="Not configured"
	    NEED_CONFIG_NODE=$(($NEED_CONFIG_NODE + 1))
	    ;;
    esac

    CURRENT_AMI_SECRET=$(${SUDO} grep '^secret\s*=\s*' "${ASTERISK_D}/manager.conf" 2>/dev/null			| \
			 sed 's/^secret\s*=\s*//;s/\s*;.*$//')
    CURRENT_AMI_SECRET_D="${CURRENT_AMI_SECRET}"
    case "${CURRENT_AMI_SECRET}" in
	"" | "llcgi" )
	    CURRENT_AMI_SECRET_D="Not configured"
	    NEED_CONFIG_NODE=$(($NEED_CONFIG_NODE + 1))
	    ;;
    esac

    if [ -d "${ALLMON_D}" ]; then
	CURRENT_ALLMON_NODE=$(${SUDO} grep '^\[' "${ALLMON_D}/allmon3.ini" 2>/dev/null				| \
				head -1										| \
				sed 's/^\[\(.*\)]$/\1/')

	CURRENT_ALLMON_SECRET=$(${SUDO} sed -n "/^\\[${CURRENT_ALLMON_NODE}]/,/pass/ P" "${ALLMON_D}/allmon3.ini" 2>/dev/null	| \
				grep "pass"									| \
				sed -e 's/pass\s*=\s*//')
    else
	CURRENT_ALLMON_NODE="${CURRENT_NODE}"
	CURRENT_ALLMON_SECRET="${CURRENT_AMI_SECRET}"
    fi

    if [ -d "${SUPERMON_D}" ]; then
	CURRENT_SUPERMON_CALL=$(${SUDO} grep '^\$CALL\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null		| \
				sed 's/.*"\(.*\)";.*/\1/')

	CURRENT_SUPERMON_NAME=$(${SUDO} grep '^\$NAME\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null		| \
				sed 's/.*"\(.*\)";.*/\1/')
	CURRENT_SUPERMON_NAME_D="${CURRENT_SUPERMON_NAME}"
	case "${CURRENT_SUPERMON_NAME}" in
	    "" | "Your NAME" )
		CURRENT_SUPERMON_NAME_D="Not configured"
		NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
		;;
	esac

	CURRENT_SUPERMON_LOCATION=$(${SUDO} grep '^\$LOCATION\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null	| \
				    sed 's/.*"\(.*\)";.*/\1/')
	CURRENT_SUPERMON_LOCATION_D="${CURRENT_SUPERMON_LOCATION}"
	case "${CURRENT_SUPERMON_LOCATION}" in
	    "" | "Edit /var/www/html/supermon/global.inc to change!" )
		CURRENT_SUPERMON_LOCATION_D="Not configured"
		NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
		;;
	esac

	CURRENT_SUPERMON_LOCALZIP=$(${SUDO} grep '^\$LOCALZIP\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null	| \
				    sed 's/.*"\(.*\)";.*/\1/')
	CURRENT_SUPERMON_LOCALZIP_D="${CURRENT_SUPERMON_LOCALZIP}"
	case "${CURRENT_SUPERMON_LOCALZIP}" in
	    "" | "93301" )
		CURRENT_SUPERMON_LOCALZIP_D="Not configured"
		NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
		;;
	esac

	CURRENT_SUPERMON_HEADER2=$(${SUDO} grep '^\$TITLE2\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null	| \
			      sed 's/.*"\(.*\)";.*/\1/')

	CURRENT_SUPERMON_HEADER3=$(${SUDO} grep '^\$TITLE3\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null	| \
			      sed 's/.*"\(.*\)";.*/\1/')

	CURRENT_SUPERMON_NODE=$(${SUDO} grep '^\[' "${SUPERMON_D}/allmon.ini" 2>/dev/null			| \
				grep -v 1998									| \
				head -1										| \
				sed 's/^\[\(.*\)]$/\1/')

	CURRENT_SUPERMON_SECRET=$(${SUDO} sed -n "/^\\[${CURRENT_SUPERMON_NODE}]/,/passwd/ P" "${SUPERMON_D}/allmon.ini" 2>/dev/null	| \
				  grep "passwd"									| \
				  sed -e 's/passwd\s*=\s*//')
    else
	CURRENT_SUPERMON_CALL="${CURRENT_CALL}"
	CURRENT_SUPERMON_NAME_D="Not used"
	CURRENT_SUPERMON_LOCATION_D="Not used"
	CURRENT_SUPERMON_LOCALZIP_D="Not used"
	CURRENT_SUPERMON_HEADER2="Not used"
	CURRENT_SUPERMON_HEADER3="Not used"
	CURRENT_SUPERMON_NODE="${CURRENT_NODE}"
	CURRENT_SUPERMON_SECRET="${CURRENT_AMI_SECRET}"
    fi

    SYNC_NODE=0
    if [ "${CURRENT_NODE}" != "${CURRENT_ALLMON_NODE}" ]; then
	SYNC_NODE=1
	NEED_NODE_WEB_SYNC=$(($NEED_NODE_WEB_SYNC + 1))
	NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
    fi
    if [ "${CURRENT_NODE}" != "${CURRENT_SUPERMON_NODE}" ]; then
	SYNC_NODE=1
	NEED_NODE_WEB_SYNC=$(($NEED_NODE_WEB_SYNC + 1))
	NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
    fi

    SYNC_CALL=0
    if [ "${CURRENT_CALL}" != "${CURRENT_SUPERMON_CALL}" ]; then
	SYNC_CALL=1
	NEED_NODE_WEB_SYNC=$(($NEED_NODE_WEB_SYNC + 1))
	NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
    fi

    SYNC_AMI_SECRET=0
    if [ "${CURRENT_AMI_SECRET}" != "${CURRENT_ALLMON_SECRET}" ]; then
	SYNC_AMI_SECRET=1
	NEED_NODE_WEB_SYNC=$(($NEED_NODE_WEB_SYNC + 1))
	NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
    fi
    if [ "${CURRENT_AMI_SECRET}" != "${CURRENT_SUPERMON_SECRET}" ]; then
	SYNC_AMI_SECRET=1
	NEED_NODE_WEB_SYNC=$(($NEED_NODE_WEB_SYNC + 1))
	NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
    fi
}

do_sync_web_with_node()
{
    if [ ${NEED_NODE_WEB_SYNC} -eq 0 ]; then
	return
    fi

    MSG="The node settings ("

    COUNT=${NEED_NODE_WEB_SYNC}
    if [ ${SYNC_NODE} -ne 0 ]; then
	MSG="${MSG}node #"
	COUNT=$(($COUNT - 1))
	if [ ${COUNT} -gt 0 ]; then
	    MSG="${MSG}, "
	fi
    fi
    if [ ${SYNC_CALL} -ne 0 ]; then
	MSG="${MSG}callsign"
	COUNT=$(($COUNT - 1))
	if [ ${COUNT} -gt 0 ]; then
	    MSG="${MSG}, "
	fi
    fi
    if [ ${SYNC_AMI_SECRET} -ne 0 ]; then
	MSG="${MSG}management interface secret"
    fi
    MSG="${MSG}) and the corresponding web application configuration"
    MSG="${MSG} settings are not in sync."
    MSG="${MSG}\n\nWould you like to update the web application"
    MSG="${MSG} configuration settings now?"
    whiptail					\
	--title "$title"			\
	--yesno					\
	"${MSG}"				\
	${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
    ANSWER=$?
    if [ ${ANSWER} -eq 0 ]; then
	#
	# Sync "Allmon3" settings
	#
	if [ "${CURRENT_NODE}" != "${CURRENT_ALLMON_NODE}" ]; then
	    echo "Sync web [allmon3] node"
	    if [ -z "${CURRENT_ALLMON_NODE}" ]; then
		cat <<_END_OF_INPUT | ${SUDO} tee -a "${ALLMON_D}/allmon3.ini"	> /dev/null

[${CURRENT_NODE}]
host=127.0.0.1
user=admin
pass=${CURRENT_AMI_SECRET}
_END_OF_INPUT
		CURRENT_ALLMON_SECRET="${CURRENT_AMI_SECRET}"
	    else
		${SUDO} sed -i "s/${CURRENT_ALLMON_NODE}/${CURRENT_NODE}/"			"${ALLMON_D}/allmon3.ini"
	    fi
	fi

	if [ "${CURRENT_AMI_SECRET}" != "${CURRENT_ALLMON_SECRET}" ]; then
	    echo "Sync web [allmon3] AMI secret"
	    ${SUDO} ex	"${ALLMON_D}/allmon3.ini"	<<_END_OF_INPUT
/^\[${CURRENT_NODE}]
/pass
s/${CURRENT_ALLMON_SECRET}/${CURRENT_AMI_SECRET}/
w
q
_END_OF_INPUT
	fi

	#
	# Sync "Supermon" settings
	#
	if [ "${CURRENT_NODE}" != "${CURRENT_SUPERMON_NODE}" ]; then
	    echo "Sync web [supermon] node"
	    ${SUDO} sed -i "s/${CURRENT_SUPERMON_NODE}/${CURRENT_NODE}/"			"${SUPERMON_D}/allmon.ini"
	fi

	if [ "${CURRENT_CALL}" != "${CURRENT_SUPERMON_CALL}" ]; then
	    echo "Sync web [supermon] call"
	    ${SUDO} sed -i "s/^\(\\\$CALL\s*=\s*\).*\(;.*\)/\1\"${CURRENT_CALL}\"\2/"	"${SUPERMON_D}/global.inc"
	fi

	if [ "${CURRENT_AMI_SECRET}" != "${CURRENT_SUPERMON_SECRET}" ]; then
	    echo "Sync web [supermon] AMI secret"
	    ${SUDO} ex	"${SUPERMON_D}/allmon.ini"	<<_END_OF_INPUT
/^\[${CURRENT_NODE}]
/passwd
s/${CURRENT_SUPERMON_SECRET}/${CURRENT_AMI_SECRET}/
w
q
_END_OF_INPUT
	fi
    fi
}

do_update_web_name()
{
    if [ ! -d "${SUPERMON_D}" ]; then
	whiptail --msgbox "Supermon not installed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	return
    fi

    CURRENT="${CURRENT_SUPERMON_NAME}"
    if [ "${CURRENT_SUPERMON_NAME_D}" = "Not configured" ]; then
	CURRENT=""
    fi

    ANSWER=$(whiptail								\
	    --title "$title"							\
	    --inputbox "Enter your name for Node ${CURRENT_NODE_D}"	\
	    ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
	    "${CURRENT}"							\
	    3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
	return
    fi

    if [ "${CURRENT_SUPERMON_NAME}" != "${ANSWER}" ]; then
	echo "Update web name"
	${SUDO} sed -i "s/^\(\\\$NAME\s*=\s*\).*\(;.*\)/\1\"${ANSWER}\"\2/"	"${SUPERMON_D}/global.inc"
    fi
}

do_update_web_location()
{
    if [ ! -d "${SUPERMON_D}" ]; then
	whiptail --msgbox "Supermon not installed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	return
    fi

    CURRENT="${CURRENT_SUPERMON_LOCATION}"
    if [ "${CURRENT_SUPERMON_LOCATION_D}" = "Not configured" ]; then
	CURRENT=""
    fi

    ANSWER=$(whiptail								\
	    --title "$title"							\
	    --inputbox "Enter your location for Node ${CURRENT_NODE_D}"	\
	    ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
	    "${CURRENT}"							\
	    3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
	return
    fi

    if [ "${CURRENT_SUPERMON_LOCATION}" != "${ANSWER}" ]; then
	echo "Update web location"
	${SUDO} sed -i "s/^\(\\\$LOCATION\s*=\s*\).*\(;.*\)/\1\"${ANSWER}\"\2/"	"${SUPERMON_D}/global.inc"
    fi
}

do_update_localzip()
{
    if [ ! -d "${SUPERMON_D}" ]; then
	whiptail --msgbox "Supermon not installed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	return
    fi

    CURRENT="${CURRENT_SUPERMON_LOCALZIP}"
    if [ "${CURRENT_SUPERMON_LOCALZIP_D}" = "Not configured" ]; then
	CURRENT=""
    fi

    while true; do
	ANSWER=$(whiptail							\
		--title "$title"						\
		--inputbox "Enter Zip Code for Node ${CURRENT_NODE_D}"		\
		${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}				\
		"${CURRENT}"							\
		3>&1 1>&2 2>&3)
	if [ $? -ne 0 ]; then
	    return
	fi

	re=^[0-9][0-9][0-9][0-9][0-9]$
	if ! [[ $ANSWER =~ $re ]]; then
	    whiptail --msgbox "Zip Code must be a 5-digit number."		\
		${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	else
	    break
	fi

	CURRENT="${ANSWER}"
    done

    if [ "${CURRENT_SUPERMON_LOCALZIP}" != "${ANSWER}" ]; then
	echo "Update web zip"
	${SUDO} sed -i "s/^\(\\\$LOCALZIP\s*=\s*\).*\(;.*\)/\1\"${ANSWER}\"\2/"	"${SUPERMON_D}/global.inc"
    fi
}

do_update_header2()
{
    if [ ! -d "${SUPERMON_D}" ]; then
	whiptail --msgbox "Supermon not installed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	return
    fi

    CURRENT="${CURRENT_SUPERMON_HEADER2}"

    ANSWER=$(whiptail								\
	    --title "$title"							\
	    --inputbox "Enter header line #2 for Node ${CURRENT_NODE_D}"	\
	    ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
	    "${CURRENT}"							\
	    3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
	return
    fi

    if [ "${CURRENT_SUPERMON_HEADER2}" != "${ANSWER}" ]; then
	echo "Update web header line 2"
	${SUDO} sed -i "s|^\(\\\$TITLE2\s*=\s*\).*\(;.*\)|\1\"${ANSWER}\"\2|"	"${SUPERMON_D}/global.inc"
    fi
}

do_update_header3()
{
    if [ ! -d "${SUPERMON_D}" ]; then
	whiptail --msgbox "Supermon not installed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	return
    fi

    CURRENT="${CURRENT_SUPERMON_HEADER3}"

    ANSWER=$(whiptail								\
	    --title "$title"							\
	    --inputbox "Enter header line #3 for Node ${CURRENT_NODE_D}"	\
	    ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
	    "${CURRENT}"							\
	    3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
	return
    fi

    if [ "${CURRENT_SUPERMON_HEADER3}" != "${ANSWER}" ]; then
	echo "Update web header line 3"
	${SUDO} sed -i "s|^\(\\\$TITLE3\s*=\s*\).*\(;.*\)|\1\"${ANSWER}\"\2|"	"${SUPERMON_D}/global.inc"
    fi
}

do_configure_web()
{
    if [ ! -d "${ALLMON_D}" ] && [ ! -d "${ALLSCAN_D}" ] && [ ! -d "${SUPERMON_D}" ] ; then
	whiptail --msgbox "No web applications have been installed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	return 0
    fi

    calc_wt_size

    while true; do
	read_asl_config " (configure web)"

	SYNC_ITEM=" "
	SYNC_ACTION=""
	if [ ${NEED_NODE_WEB_SYNC} -gt 0 ]; then
	    SYNC_ITEM="9"
	    SYNC_ACTION="Syncronize node and web settings"
	fi

	DEFAULT=0
	if   [ "${CURRENT_NODE_D}"         = "Not configured" ]; then
	    DEFAULT=1
	elif [ "${CURRENT_CALL_D}"         = "Not configured" ]; then
	    DEFAULT=2
	elif [ "${CURRENT_AMI_SECRET_D}"   = "Not configured" ]; then
	    DEFAULT=3
	elif [ "${CURRENT_SUPERMON_NAME_D}"     = "Not configured" ]; then
	    DEFAULT=4
	elif [ "${CURRENT_SUPERMON_LOCATION_D}" = "Not configured" ]; then
	    DEFAULT=5
	elif [ "${CURRENT_SUPERMON_LOCALZIP_D}" = "Not configured" ]; then
	    DEFAULT=6
	elif [ ${NEED_NODE_WEB_SYNC} -gt 0                    ]; then
	    DEFAULT=9
	fi

	ANSWER=$(whiptail						\
		--menu "AllStarLink Update Web App Configuration"	\
		${WT_HEIGHT}						\
		${WT_WIDTH}						\
		${WT_MENU_HEIGHT}					\
		--ok-button	"Select"				\
		--cancel-button	"Exit Menu"				\
		--default-item	${DEFAULT}				\
		"1" "Node #              : ${CURRENT_NODE_D}" 		\
		"2" "Node Callsign       : ${CURRENT_CALL_D}"		\
		"3" "AMI Secret          : ${CURRENT_AMI_SECRET_D}"	\
		" " ""							\
		"4" "Your Name           : ${CURRENT_SUPERMON_NAME_D}"	\
		"5" "Your Location       : ${CURRENT_SUPERMON_LOCATION_D}"	\
		"6" "Your Zipcode        : ${CURRENT_SUPERMON_LOCALZIP_D}"	\
		" " ""							\
		"7" "Supermon Header (2) : ${CURRENT_SUPERMON_HEADER2}"	\
		"8" "Supermon Header (3) : ${CURRENT_SUPERMON_HEADER3}"	\
		" " ""							\
		"${SYNC_ITEM}" "${SYNC_ACTION}"				\
		3>&1 1>&2 2>&3)
	if [ $? -ne 0 ]; then
	    break
	fi

	case "${ANSWER}" in
	    1)	do_configure_node		;;
	    2)	do_configure_node		;;
	    3)	do_configure_node		;;
	    4)	do_update_web_name		;;
	    5)	do_update_web_location		;;
	    6)	do_update_localzip		;;
	    7)	do_update_header2		;;
	    8)	do_update_header3		;;
	    9)	do_sync_web_with_node		;;
	    " ")				;;
	    *)	whiptail --msgbox "\"${ANSWER}\" is an unrecognized selection."		\
			${MSGBOX_HEIGHT} ${MSGBOX_WIDTH} ;;
	esac || whiptail --msgbox "There was an error running option \"${ANSWER}\""	\
			${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
    done

    if [ ${NEED_NODE_WEB_SYNC} -gt 0 ]; then
	do_sync_web_with_node
    fi
}

do_finish()
{
    MSG="Setup is complete. Settings will take effect on next boot."
    MSG="${MSG}\n\nWould you like to reboot now?"
    whiptail					\
	--title "$title"			\
	--yesno					\
	--defaultno				\
	"${MSG}"				\
	${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
    ANSWER=$?
    if [ ${ANSWER} -eq 0 ]; then
	sync
	sleep 1
	${SUDO} reboot
    else
	exit 0
    fi
}

check_reboot_needed()
{
    if [[ $SKIP_REBOOT_CHECK -ne 0 ]]; then
	# if we've previously blessed using an [old] kernel
	return 0
    fi

    KERNEL_RUNNING="/boot/vmlinuz-$(uname -r)"
    KERNEL_INSTALL=$(ls -1 /boot/vmlinuz* 2>/dev/null | sort -V | tail -1)

    if [[ -z "${KERNEL_INSTALL}" ]]; then
	# no "vmlinuz" kernel ???
	return 0
    fi

    if [[ "${KERNEL_RUNNING}" != "${KERNEL_INSTALL}" ]]; then
	#
	# the running kernel differs from latest installed kernel
	#
	MSG="It appears that the OS kernel was recently updated.  This"
	MSG="${MSG} system should be rebooted before building, installing,"
	MSG="${MSG} or updating the AllStarLink software."
	MSG="${MSG}\n\nNote: after the reboot you should re-exec this"
	MSG="${MSG} command and start again at the first step (Setup)"
	MSG="${MSG}\n\nWould you like to reboot now?"
	whiptail				\
	    --title "$title"			\
	    --yesno				\
	    "${MSG}"				\
	    ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	ANSWER=$?
	if [ ${ANSWER} -eq 0 ]; then
	    sync
	    sleep 1
	    ${SUDO} reboot
	fi

	# if we've opted to keep going
	SKIP_REBOOT_CHECK=1
	return 1
    fi

    return 0
}

do_web_apps()
{
    DO_ALLMON="?"
    if [ -d "${ALLMON_D}" ]; then
	DO_ALLMON=""
    fi

    DO_ALLSCAN="?"
    if [ -d "${ALLSCAN_D}" ]; then
	DO_ALLSCAN=""
    fi

    DO_SUPERMON="?"
    if [ -d "${SUPERMON_D}" ]; then
	DO_SUPERMON=""
    fi

    while true; do
	calc_wt_size

	read_asl_config " (web app loop)"

	DO_CONFIG_WEB=""
	if [ ${NEED_CONFIG_WEB} -gt 0 ]; then
	    DO_CONFIG_WEB="***"
	fi

	DEFAULT=0
	if [ ${NEED_CONFIG_WEB}  -gt 0 ]; then
	    DO_CONFIG_WEB="<--"
	    DEFAULT=4
	fi

	ANSWER=$(whiptail							\
		--menu "AllStarLink Web Application Menu"			\
		${WT_HEIGHT}							\
		${WT_WIDTH}							\
		${WT_MENU_HEIGHT}						\
		--ok-button	"Select"					\
		--cancel-button	"Exit Menu"					\
		--default-item	${DEFAULT}					\
		"1" "Build/install Allmon3               ${DO_ALLMON}"		\
		"2" "Build/install Supermon              ${DO_SUPERMON}"	\
		"3" "Build/install AllScan               ${DO_ALLSCAN}"		\
		"4" "Configure web application settings  ${DO_CONFIG_WEB}"	\
		3>&1 1>&2 2>&3)
	if [ $? -ne 0 ]; then
	    return $?
	fi

	case "${ANSWER}" in
	    1)	do_allmon		;;
	    2)	do_supermon		;;
	    3)	do_allscan		;;
	    4)	do_configure_web	;;
	    *)	whiptail --msgbox "\"${ANSWER}\" is an unrecognized selection."		\
			${MSGBOX_HEIGHT} ${MSGBOX_WIDTH} ;;
	esac || whiptail --msgbox "There was an error running option \"${ANSWER}\""	\
			${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
    done
}

do_cleanup()
{

    MSG="This step will remove the downloaded content used to \"build\" "
    MSG="${MSG}and \"install\" the AllStarlink components.  Performing "
    MSG="${MSG}this step is completely safe and will not affect your ASL "
    MSG="${MSG}node or it's configuration.  Should you want (or need) to "
    MSG="${MSG}repeat any of the earlier steps then you will need to start "
    MSG="${MSG}again with the \"Setup\" step."
    MSG="${MSG}\n\nWould you like to perform the cleanup now?"

    whiptail			\
	--title "$title"	\
	--yesno			\
	"${MSG}"		\
	${WT_HEIGHT} ${WT_WIDTH}
    ANSWER=$?
    if [ "${ANSWER}" != "0" ]; then
	return
    fi

    for d in			\
	ASL-Asterisk		\
	ASL-DAHDI		\
	ASL-Nodes-Diff		\
	ASL-Supermon		\
	AllScan			\
	Allmon3			\

    do
	rm -r -f "${d}"
    done

    return
}

check_web_apps_available()
{
    # check if we have all of the ASL components
    for f in						\
	"${DESTDIR}/usr/sbin/asterisk"			\
	"${DESTDIR}/usr/sbin/asl-menu"			\
	"${DESTDIR}/usr/sbin/update-node-list.sh"	\

    do
	if [ ! -x "${f}" ]; then
	    return 0
	fi
    done

    # check if we could install any of the [optional] web apps
    for d in						\
	"${ALLMON_D}"					\
	"${ALLSCAN_D}"					\
	"${SUPERMON_D}"					\

    do
	if [ ! -d "${d}" ]; then
	    return 1
	fi
    done

    return 0
}

do_main_menu()
{
    while true; do
	calc_wt_size

	check_reboot_needed

	read_asl_config " (main menu loop)"

	DO_CONFIG_NODE=""
	if [ ${NEED_CONFIG_NODE} -gt 0 ]; then
	    DO_CONFIG_NODE="***"
	fi

	DO_CONFIG_WEB=""
	if [ ${NEED_CONFIG_WEB} -gt 0 ]; then
	    DO_CONFIG_WEB="***"
	fi

	DO_WEB_APPS=""
	check_web_apps_available
	if [ $? -ne 0 ]; then
	    DO_WEB_APPS="?"
	fi

	DEFAULT=0
	if   [ "$DO_SETUP"      = "<--" ]; then
	    DEFAULT=1
	elif [ "$DO_PREPARE"    = "<--" ]; then
	    DEFAULT=2
	elif [ "$DO_DAHDI"      = "<--" ]; then
	    DEFAULT=3
	elif [ "$DO_ASTERISK"   = "<--" ]; then
	    DEFAULT=4
	elif [ "$DO_ALLSTAR"    = "<--" ]; then
	    DEFAULT=5
	elif [ "$DO_NODES_DIFF" = "<--" ]; then
	    DEFAULT=6
	elif [ ${NEED_CONFIG_NODE} -gt 0 ]; then
	    DO_CONFIG_NODE="<--"
	    DEFAULT=8
	elif [ ${NEED_CONFIG_WEB}  -gt 0 ]; then
	    DO_CONFIG_WEB="<--"
	    DEFAULT=9
	fi

	ANSWER=$(whiptail							\
		--menu "AllStarLink Build & Installation Menu"			\
		${WT_HEIGHT}							\
		${WT_WIDTH}							\
		${WT_MENU_HEIGHT}						\
		--ok-button	"Select"					\
		--cancel-button	"Exit Menu"					\
		--default-item	${DEFAULT}					\
		"1"  "Setup                               ${DO_SETUP}"		\
		"2"  "Prepare                             ${DO_PREPARE}"	\
		"3"  "Build/install DAHDI                 ${DO_DAHDI}"		\
		"4"  "Build/install Asterisk              ${DO_ASTERISK}"	\
		"5"  "Build/install AllStar               ${DO_ALLSTAR}"	\
		"6"  "Build/install Nodes-Diff            ${DO_NODES_DIFF}"	\
		"7"  "Build/install Web apps (optional)   ${DO_WEB_APPS}"	\
		"8"  "Configure node settings             ${DO_CONFIG_NODE}"	\
		"9"  "Configure web application settings  ${DO_CONFIG_WEB}"	\
		"10" "Cleanup"							\
		3>&1 1>&2 2>&3)
	if [ $? -ne 0 ]; then
	    do_finish
	    exit
	fi

	case "${ANSWER}" in
	    1)	do_setup		;;
	    2)	do_prepare		;;
	    3)	do_dahdi		;;
	    4)	do_asterisk		;;
	    5)	do_allstar		;;
	    6)	do_nodes_diff		;;
	    7)	do_web_apps		;;
	    8)	do_configure_node	;;
	    9)	do_configure_web	;;
	    10)	do_cleanup		;;
	    *)	whiptail --msgbox "\"${ANSWER}\" is an unrecognized selection."		\
			${MSGBOX_HEIGHT} ${MSGBOX_WIDTH} ;;
	esac || whiptail --msgbox "There was an error running option \"${ANSWER}\""	\
			${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
    done
}

do_welcome
do_main_menu

exit
