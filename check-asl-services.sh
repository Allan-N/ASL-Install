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

else

    echo "What OS?"
    exit 1

fi
