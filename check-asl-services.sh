#!/bin/bash

if [ -f /etc/amazon-linux-release ]; then

    # Check [ASL] dahdi
#   echo ""
    systemctl --no-pager status dahdi

    # Check [ASL] asterisk
    echo ""
    systemctl --no-pager status asterisk

    # Check that the AllStarLink node list updater
    echo ""
    systemctl --no-pager status update-node-list

    # Check the web server
    echo ""
    apachectl status

    if [ -d /etc/allmon3 ]; then
	echo ""
	systemctl --no-pager status allmon3
    fi

elif [ -f /etc/debian_version ]; then

    # Check [ASL] dahdi
#   echo ""
    systemctl --no-pager status dahdi

    # Check [ASL] asterisk
    echo ""
    systemctl --no-pager status asterisk

    # Check that the AllStarLink node list updater
    echo ""
    systemctl --no-pager status update-node-list

    # Check the web server
    echo ""
    systemctl --no-pager status apache2

    if [ -d /etc/allmon3 ]; then
	echo ""
	systemctl --no-pager status allmon3
    fi

else

    echo "What OS?"
    exit 1

fi
