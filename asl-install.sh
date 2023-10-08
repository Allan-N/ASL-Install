#!/bin/bash
#
# asl-build-install
# v1.0	WA3WCO	2023/09/07

title="AllStarLink Build and Install"

DO_SETUP="<--"
DO_CLEAN=""
DO_DAHDI=""
DO_ASTERISK=""
DO_ALLSTAR=""
DO_NODES_DIFF=""
DO_SUPERMON=""
DO_ALLSCAN=""
DO_FINISH=""

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

DESTDIR=""
#DESTDIR="/tmp/asl-install-root"
if [ "${DESTDIR}" != "" ]; then
    ${SUDO} mkdir -p "${DESTDIR}"
fi

ASTERISK_D="${DESTDIR}/etc/asterisk"
SUPERMON_D="${DESTDIR}/var/www/html/supermon"

calc_wt_size()
{
    # Bash knows the terminal size
    #   The number of columns are $COLUMNS
    #   The number of lines are $LINES

    if [ $LINES -lt 22 ]; then
	echo "Teaminal size must be at least 22 lines."
	exit
    fi
    if [ $COLUMNS -lt 60 ]; then
	echo "Teaminal size must be at least 60 columns."
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
    if [ "${ANSWER}" = "0" ]; then #answered yes
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

	${SUDO} yum autoremove
    elif [ -x /usr/bin/apt ]; then
	${SUDO} apt update

	${SUDO} apt -y install		\
		apache2			\
		autoconf		\
		automake		\
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
		php			\
		pkg-config		\
		zip			\

	${SUDO} apt autoremove
    else
	echo "Unsupported OS"
	exit 1
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
	"https://github.com/AllStarLink/ASL-DAHDI.git"		\
	"https://github.com/Allan-N/ASL-Asterisk.git"		\
	"https://github.com/AllStarLink/ASL-Nodes-Diff.git"	\
	"https://github.com/Allan-N/ASL-Supermon.git"		\
	"https://github.com/Allan-N/AllScan.git"		\

    do
	r=$(basename ${url})
	d=$(basename ${r} .git)
	if [ ! -d ${d} ]; then
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
    LOGIN_USER=$(who am i | awk '{print $1}')
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
    DO_CLEAN="<--"
}

do_clean()
{
    echo "CLEAN the [AllStarLink] packages"

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
    DO_CLEAN="OK"
    DO_DAHDI="<--"
}

do_dahdi()
{
    echo "Build/install DAHDI"								| tee /var/tmp/build-dahdi.txt

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

    echo "* autoreconf"									| tee -a /var/tmp/build-dahdi.txt
    (cd ASL-DAHDI/tools;		autoreconf --install --force)			>> /var/tmp/build-dahdi.txt	2>&1
    if [ $? -ne 0 ]; then
	whiptail --msgbox "ASL-DAHDI/tools autoreconf failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make"									| tee -a /var/tmp/build-dahdi.txt
    make -C ASL-DAHDI MODULES_EXTRA="dahdi_dummy"					>> /var/tmp/build-dahdi.txt	2>&1
    if [ $? -ne 0 ]; then
	whiptail --msgbox "ASL-DAHDI build failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make install"								| tee -a /var/tmp/build-dahdi.txt
    ${SUDO} make -C ASL-DAHDI install MODULES_EXTRA="dahdi_dummy" DESTDIR="${DESTDIR}"	>> /var/tmp/build-dahdi.txt	2>&1
    if [ $? -ne 0 ]; then
	whiptail --msgbox "ASL-DAHDI install failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make config"								| tee -a /var/tmp/build-dahdi.txt
    ${SUDO} make -C ASL-DAHDI config				DESTDIR="${DESTDIR}"	>> /var/tmp/build-dahdi.txt	2>&1
    if [ $? -ne 0 ]; then
	whiptail --msgbox "ASL-DAHDI install failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make tools/install-config"							| tee -a /var/tmp/build-dahdi.txt
    HACK="/var/tmp/build-dahdi.txt-$$"
    ${SUDO} make -C ASL-DAHDI/tools install-config		DESTDIR="${DESTDIR}"	>  ${HACK}			2>&1
    STATUS=$?
    cat ${HACK}										>> /var/tmp/build-dahdi.txt
    rm -f ${HACK}
    if [ $STATUS -ne 0 ]; then
	whiptail --msgbox "ASL-DAHDI/tools install-config failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    if [ -f "${DESTDIR}/etc/dahdi/system.conf.sample" -a ! -f "${DESTDIR}/etc/dahdi/system.conf" ]; then
	${SUDO} install						\
		-m 644						\
		"${DESTDIR}/etc/dahdi/system.conf.sample"	\
		"${DESTDIR}/etc/dahdi/system.conf"
    fi

    if [ "$DO_SETUP" = "<--" ]; then
	DO_SETUP=""
    fi
    if [ "$DO_CLEAN" = "<--" ]; then
	DO_CLEAN=""
    fi
    DO_DAHDI="OK"
    DO_ASTERISK="<--"
}

do_asterisk()
{
    if [ ! -f /usr/include/dahdi/tonezone.h -o ! -f /etc/modprobe.d/dahdi.conf ]; then
	whiptail --msgbox "DAHDI not built/installed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "Build/install Asterisk"							| tee /var/tmp/build-asterisk.txt

    echo "* autoreconf"									| tee -a /var/tmp/build-asterisk.txt
    (cd ASL-Asterisk/asterisk;		autoreconf --install --force)			>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	whiptail --msgbox "ASL-Asterisk autoreconf failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* configure"									| tee -a /var/tmp/build-asterisk.txt
    (cd ASL-Asterisk/asterisk;		./configure)					>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	whiptail --msgbox "ASL-Asterisk configure failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make		(Note: this make take a while)"				| tee -a /var/tmp/build-asterisk.txt
    make -C ASL-Asterisk/asterisk							>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	whiptail --msgbox "ASL-Asterisk build failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make install"								| tee -a /var/tmp/build-asterisk.txt
    ${SUDO} make -C ASL-Asterisk/asterisk install		DESTDIR="${DESTDIR}"	>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	whiptail --msgbox "ASL-Asterisk install failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make config"								| tee -a /var/tmp/build-asterisk.txt
    ${SUDO} make -C ASL-Asterisk/asterisk config		DESTDIR="${DESTDIR}"	>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	whiptail --msgbox "ASL-Asterisk config failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    echo "* make samples"								| tee -a /var/tmp/build-asterisk.txt
    ${SUDO} make -C ASL-Asterisk/asterisk samples OVERWRITE="n"	DESTDIR="${DESTDIR}"	>> /var/tmp/build-asterisk.txt	2>&1
    if [ $? -ne 0 ]; then
	whiptail --msgbox "ASL-Asterisk samples failed" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	exit 1
    fi

    if [ -f ${DESTDIR}/etc/asterisk/modules.conf -a ! -f ASL-Asterisk/asterisk/codecs/codec_ilbc.o ]; then	\
	${SUDO} sed -i 's/\(^load .* codec_ilbc.so .*\)/no\1/'	${DESTDIR}/etc/asterisk/modules.conf;		\
    fi

    if [ "$DO_SETUP" = "<--" ]; then
	DO_SETUP=""
    fi
    if [ "$DO_CLEAN" = "<--" ]; then
	DO_CLEAN=""
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
    DO_SUPERMON="<--"
}

do_supermon()
{
    echo "Build/install Supermon"

    check_www
    if [ $? -ne 0 ]; then
	return
    fi

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
    # if needed, add .htpasswd
    #
    SUPERMON_PASSWD="${DESTDIR}/var/www/html/supermon/.htpasswd"
    if [ ! -f "${SUPERMON_PASSWD}" ]; then
	SUPERMON_USER=""
	while [ "${SUPERMON_USER}" = "" ]; do
	    SUPERMON_USER=$(whiptail							\
		--title "$title"							\
		--inputbox "Enter \"Supermon\" login for Node ${CURRENT_NODE_D}"	\
		${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
		3>&1 1>&2 2>&3)
	    if [ $? -ne 0 ]; then
		return
	    fi
	done

	SUPERMON_PASS="A"
	SUPERMON_PASS2="B"
        while [ "${SUPERMON_PASS}" != "${SUPERMON_PASS2}" ]; do
	    SUPERMON_PASS=$(whiptail							\
		--title "$title"							\
		--passwordbox "Enter \"Supermon\" password for login ${SUPERMON_USER}"	\
		${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
		3>&1 1>&2 2>&3)
	    if [ $? -ne 0 ]; then
		return
	    fi

	    SUPERMON_PASS2=$(whiptail							\
		--title "$title"							\
		--passwordbox "Verify \"Supermon\" password for login ${SUPERMON_USER}"	\
		${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
		3>&1 1>&2 2>&3)
	    if [ $? -ne 0 ]; then
		return
	    fi

            if [ "${SUPERMON_PASS}" != "${SUPERMON_PASS2}" ]; then
		whiptail --msgbox "Passwords must match" ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
	    fi
        done

	htpasswd -i -c -B "${SUPERMON_PASSWD}" ${SUPERMON_USER} <<_END_OF_INPUT
${SUPERMON_PASS}
_END_OF_INPUT
    fi

    #
    # if needed, add .htaccess
    #
    SUPERMON_ACCESS="${DESTDIR}/var/www/html/supermon/.htaccess"
    if [ ! -f "${SUPERMON_ACCESS}" ]; then
	cat <<_END_OF_INPUT | sudo tee "${SUPERMON_ACCESS}"		> /dev/null
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
	cat <<_END_OF_INPUT | sudo tee "${SUPERMON_SUDOERS}"		> /dev/null
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

    DO_SUPERMON="OK"
    DO_ALLSCAN="<--"
}

do_allscan()
{
    echo "Build/install AllScan"

    check_www
    if [ $? -ne 0 ]; then
	return
    fi

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

    DO_ALLSCAN="OK"
    DO_FINISH="<--"
}

do_configure_node()
{
    if [ ! -x /usr/sbin/node-setup ]; then
	return
    fi

    MSG="Set up hotspot/repeater, node number, and other AllStar settings."
    MSG="${MSG}\n\nWould you like to change AllStar settings?"
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

    CURRENT_NODE=$(grep -o '^\[[0-9]*\]' "${ASTERISK_D}/rpt.conf" 2>/dev/null			| sed 's/^.//;s/.$//')
    CURRENT_NODE_D="${CURRENT_NODE}"
    case "${CURRENT_NODE}" in
	"" | "1999" )
	    CURRENT_NODE_D="Not configured"
	    NEED_CONFIG_NODE=$(($NEED_CONFIG_NODE + 1))
	    ;;
    esac

    CURRENT_CALL=$(grep '^idrecording\s*=\s*' "${ASTERISK_D}/rpt.conf" 2>/dev/null		| sed 's/.*|i\([0-9a-zA-Z/-]*\).*/\1/')
    CURRENT_CALL_D="${CURRENT_CALL}"
    case "${CURRENT_CALL}" in
	"" | "WB6NIL" )
	    CURRENT_CALL_D="Not configured"
	    NEED_CONFIG_NODE=$(($NEED_CONFIG_NODE + 1))
	    ;;
    esac

    CURRENT_AMI_SECRET=$(grep '^secret\s*=\s*' "${ASTERISK_D}/manager.conf" 2>/dev/null		| sed 's/^secret\s*=\s*//;s/\s*;.*$//')
    CURRENT_AMI_SECRET_D="${CURRENT_AMI_SECRET}"
    case "${CURRENT_AMI_SECRET}" in
	"" | "llcgi" )
	    CURRENT_AMI_SECRET_D="Not configured"
	    NEED_CONFIG_NODE=$(($NEED_CONFIG_NODE + 1))
	    ;;
    esac

    CURRENT_WEB_CALL=$(grep '^\$CALL\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null		| sed 's/.*"\(.*\)";.*/\1/')

    CURRENT_WEB_NAME=$(grep '^\$NAME\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null		| sed 's/.*"\(.*\)";.*/\1/')
    CURRENT_WEB_NAME_D="${CURRENT_WEB_NAME}"
    case "${CURRENT_WEB_NAME}" in
	"" | "Your NAME" )
	    CURRENT_WEB_NAME_D="Not configured"
	    NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
	    ;;
    esac

    CURRENT_WEB_LOCATION=$(grep '^\$LOCATION\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null	| sed 's/.*"\(.*\)";.*/\1/')
    CURRENT_WEB_LOCATION_D="${CURRENT_WEB_LOCATION}"
    case "${CURRENT_WEB_LOCATION}" in
	"" | "Edit /var/www/html/supermon/global.inc to change!" )
	    CURRENT_WEB_LOCATION_D="Not configured"
	    NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
	    ;;
    esac

    CURRENT_WEB_LOCALZIP=$(grep '^\$LOCALZIP\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null	| sed 's/.*"\(.*\)";.*/\1/')
    CURRENT_WEB_LOCALZIP_D="${CURRENT_WEB_LOCALZIP}"
    case "${CURRENT_WEB_LOCALZIP}" in
	"" | "93301" )
	    CURRENT_WEB_LOCALZIP_D="Not configured"
	    NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
	    ;;
    esac

    CURRENT_WEB_HEADER2=$(grep '^\$TITLE2\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null	| sed 's/.*"\(.*\)";.*/\1/')

    CURRENT_WEB_HEADER3=$(grep '^\$TITLE3\s*=\s*' "${SUPERMON_D}/global.inc" 2>/dev/null	| sed 's/.*"\(.*\)";.*/\1/')

    CURRENT_WEB_NODE=$(grep '^\[' "${SUPERMON_D}/allmon.ini" 2>/dev/null | grep -v 1998 | head -1 | sed 's/^\[\(.*\)]$/\1/')

    CURRENT_WEB_AMI_SECRET=$(sed -n "/^\\[${CURRENT_WEB_NODE}]/,/passwd/ P" "${SUPERMON_D}/allmon.ini" 2>/dev/null	| \
			     grep "passwd"										| \
			     sed -e 's/passwd\s*=\s*//')

    SYNC_NODE=0
    if [ "${CURRENT_NODE}" != "${CURRENT_WEB_NODE}" ]; then
	SYNC_NODE=1
	NEED_NODE_WEB_SYNC=$(($NEED_NODE_WEB_SYNC + 1))
	NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
    fi

    SYNC_CALL=0
    if [ "${CURRENT_CALL}" != "${CURRENT_WEB_CALL}" ]; then
	SYNC_CALL=1
	NEED_NODE_WEB_SYNC=$(($NEED_NODE_WEB_SYNC + 1))
	NEED_CONFIG_WEB=$(($NEED_CONFIG_WEB + 1))
    fi

    SYNC_AMI_SECRET=0
    if [ "${CURRENT_AMI_SECRET}" != "${CURRENT_WEB_AMI_SECRET}" ]; then
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
	if [ "${CURRENT_NODE}" != "${CURRENT_WEB_NODE}" ]; then
	    echo "Sync web node"
	    ${SUDO} sed -i "s/${CURRENT_WEB_NODE}/${CURRENT_NODE}/"			"${SUPERMON_D}/allmon.ini"
	fi

	if [ "${CURRENT_CALL}" != "${CURRENT_WEB_CALL}" ]; then
	    echo "Sync web call"
	    ${SUDO} sed -i "s/^\(\\\$CALL\s*=\s*\).*\(;.*\)/\1\"${CURRENT_CALL}\"\2/"	"${SUPERMON_D}/global.inc"
	fi

	if [ "${CURRENT_AMI_SECRET}" != "${CURRENT_WEB_AMI_SECRET}" ]; then
	    echo "Sync web AMI secret"
	    ${SUDO} ex	"${SUPERMON_D}/allmon.ini"	<<_END_OF_INPUT
/^\[${CURRENT_NODE}]
/passwd
s/${CURRENT_WEB_AMI_SECRET}/${CURRENT_AMI_SECRET}/
w
q
_END_OF_INPUT
	fi
    fi
}

do_update_web_name()
{
    CURRENT="${CURRENT_WEB_NAME}"
    if [ "${CURRENT_WEB_NAME_D}" = "Not configured" ]; then
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

    if [ "${CURRENT_WEB_NAME}" != "${ANSWER}" ]; then
	echo "Update web name"
	${SUDO} sed -i "s/^\(\\\$NAME\s*=\s*\).*\(;.*\)/\1\"${ANSWER}\"\2/"	"${SUPERMON_D}/global.inc"
    fi
}

do_update_web_location()
{
    CURRENT="${CURRENT_WEB_LOCATION}"
    if [ "${CURRENT_WEB_LOCATION_D}" = "Not configured" ]; then
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

    if [ "${CURRENT_WEB_LOCATION}" != "${ANSWER}" ]; then
	echo "Update web location"
	${SUDO} sed -i "s/^\(\\\$LOCATION\s*=\s*\).*\(;.*\)/\1\"${ANSWER}\"\2/"	"${SUPERMON_D}/global.inc"
    fi
}

do_update_localzip()
{
    CURRENT="${CURRENT_WEB_LOCALZIP}"
    if [ "${CURRENT_WEB_LOCALZIP_D}" = "Not configured" ]; then
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

    if [ "${CURRENT_WEB_LOCALZIP}" != "${ANSWER}" ]; then
	echo "Update web zip"
	${SUDO} sed -i "s/^\(\\\$LOCALZIP\s*=\s*\).*\(;.*\)/\1\"${ANSWER}\"\2/"	"${SUPERMON_D}/global.inc"
    fi
}

do_update_header2()
{
    CURRENT="${CURRENT_WEB_HEADER2}"

    ANSWER=$(whiptail								\
	    --title "$title"							\
	    --inputbox "Enter header line #2 for Node ${CURRENT_NODE_D}"	\
	    ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
	    "${CURRENT}"							\
	    3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
	return
    fi

    if [ "${CURRENT_WEB_HEADER2}" != "${ANSWER}" ]; then
	echo "Update web header line 2"
	${SUDO} sed -i "s/^\(\\\$TITLE2\s*=\s*\).*\(;.*\)/\1\"${ANSWER}\"\2/"	"${SUPERMON_D}/global.inc"
    fi
}

do_update_header3()
{
    CURRENT="${CURRENT_WEB_HEADER3}"

    ANSWER=$(whiptail								\
	    --title "$title"							\
	    --inputbox "Enter header line #3 for Node ${CURRENT_NODE_D}"	\
	    ${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}					\
	    "${CURRENT}"							\
	    3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
	return
    fi

    if [ "${CURRENT_WEB_HEADER3}" != "${ANSWER}" ]; then
	echo "Update web header line 3"
	${SUDO} sed -i "s/^\(\\\$TITLE3\s*=\s*\).*\(;.*\)/\1\"${ANSWER}\"\2/"	"${SUPERMON_D}/global.inc"
    fi
}

do_configure_web()
{
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
	elif [ "${CURRENT_WEB_NAME_D}"     = "Not configured" ]; then
	    DEFAULT=4
	elif [ "${CURRENT_WEB_LOCATION_D}" = "Not configured" ]; then
	    DEFAULT=5
	elif [ "${CURRENT_WEB_LOCALZIP_D}" = "Not configured" ]; then
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
		"4" "Your Name           : ${CURRENT_WEB_NAME_D}"	\
		"5" "Your Location       : ${CURRENT_WEB_LOCATION_D}"	\
		"6" "Your Zipcode        : ${CURRENT_WEB_LOCALZIP_D}"	\
		" " ""							\
		"7" "Supermon Header (2) : ${CURRENT_WEB_HEADER2}"	\
		"8" "Supermon Header (3) : ${CURRENT_WEB_HEADER3}"	\
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
    MSG="${MSG}\n\nWould you like to reboot now"
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

do_main_menu()
{
    while true; do
	calc_wt_size

	read_asl_config " (main menu loop)"

	DO_CONFIG_NODE=""
	if [ ${NEED_CONFIG_NODE} -gt 0 ]; then
	    DO_CONFIG_NODE="***"
	fi

	DO_CONFIG_WEB=""
	if [ ${NEED_CONFIG_WEB} -gt 0 ]; then
	    DO_CONFIG_WEB="***"
	fi

	DEFAULT=0
	if   [ "$DO_SETUP"      = "<--" ]; then
	    DEFAULT=1
	elif [ "$DO_CLEAN"      = "<--" ]; then
	    DEFAULT=2
	elif [ "$DO_DAHDI"      = "<--" ]; then
	    DEFAULT=3
	elif [ "$DO_ASTERISK"   = "<--" ]; then
	    DEFAULT=4
	elif [ "$DO_ALLSTAR"    = "<--" ]; then
	    DEFAULT=5
	elif [ "$DO_NODES_DIFF" = "<--" ]; then
	    DEFAULT=6
	elif [ "$DO_SUPERMON"   = "<--" ]; then
	    DEFAULT=7
	elif [ "$DO_ALLSCAN"    = "<--" ]; then
	    DEFAULT=8
	elif [ ${NEED_CONFIG_NODE} -gt 0 ]; then
	    DO_CONFIG_NODE="<--"
	    DEFAULT=9
	elif [ ${NEED_CONFIG_WEB}  -gt 0 ]; then
	    DO_CONFIG_WEB="<--"
	    DEFAULT=10
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
		"2"  "Clean before build                  ${DO_CLEAN}"		\
		"3"  "Build/install DAHDI                 ${DO_DAHDI}"		\
		"4"  "Build/install Asterisk              ${DO_ASTERISK}"	\
		"5"  "Build/install AllStar               ${DO_ALLSTAR}"	\
		"6"  "Build/install Nodes-Diff            ${DO_NODES_DIFF}"	\
		"7"  "Build/install Supermon              ${DO_SUPERMON}"	\
		"8"  "Build/install AllScan               ${DO_ALLSCAN}"	\
		"9"  "Configure node settings             ${DO_CONFIG_NODE}"	\
		"10" "Configure web application settings  ${DO_CONFIG_WEB}"	\
		3>&1 1>&2 2>&3)
	if [ $? -ne 0 ]; then
	    do_finish
	    exit
	fi

	case "${ANSWER}" in
	    1)	do_setup		;;
	    2)	do_clean		;;
	    3)	do_dahdi		;;
	    4)	do_asterisk		;;
	    5)	do_allstar		;;
	    6)	do_nodes_diff		;;
	    7)	do_supermon		;;
	    8)	do_allscan		;;
	    9)  do_configure_node	;;
	    10)	do_configure_web	;;
	    *)	whiptail --msgbox "\"${ANSWER}\" is an unrecognized selection."		\
			${MSGBOX_HEIGHT} ${MSGBOX_WIDTH} ;;
	esac || whiptail --msgbox "There was an error running option \"${ANSWER}\""	\
			${MSGBOX_HEIGHT} ${MSGBOX_WIDTH}
    done
}

do_welcome
do_main_menu

exit
