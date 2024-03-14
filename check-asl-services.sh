#!/bin/bash

if [ -f /etc/amazon-linux-release ]; then

    # Check [ASL] dahdi
    systemctl status dahdi

    # Check [ASL] asterisk
    systemctl status asterisk

    # Check that the AllStarLink node list updater
    systemctl status update-node-list

    # Check the web server
    apachectl status

    if [ -d /etc/allmon3 ]; then
	systemctl status allmon3
    fi

elif [ -f /etc/debian_version ]; then

    # Check [ASL] dahdi
    systemctl status dahdi

    # Check [ASL] asterisk
    systemctl status asterisk

    # Check that the AllStarLink node list updater
    systemctl status update-node-list

    # Check the web server
    systemctl status apache2

    if [ -d /etc/allmon3 ]; then
	systemctl status allmon3
    fi

else

    echo "What OS?"
    exit 1

fi
