# ASL-Install

### This project was [originally] focused on the steps needed to build, install, and configure an AllStarLink node running on a virtual machine [VM] in the cloud.

### That focus has not precluded efforts to support other deployments (e.g. a DELL Wyse 3040 and Raspberry Pi running Debian).

## Target Operating System(s)

This package has been tested on :

* Amazon Linux 2023
* Debian 12.5 "bookworm"
* Ubuntu 22.04 LTS "jammy"

I have had success using the Raspberry Pi Imager application, selecting :

```
Raspberry Pi Device : "Raspberry Pi 4"
Operating System    : "Raspberry Pi OS (other)", "Raspberry Pi OS Lite (64-bit)"
```

### Packages installed

* ASL-DAHDI
	* [https://github.com/AllStarLink/ASL-DAHDI.git](https://github.com/AllStarLink/ASL-DAHDI.git)
	* **[https://github.com/Allan-N/ASL-DAHDI.git](https://github.com/Allan-N/ASL-DAHDI.git) (my fork w/changes)**
* ASL-Asterisk
	* [https://github.com/AllStarLink/ASL-Asterisk](https://github.com/AllStarLink/ASL-Asterisk) (main repo)
	* **[https://github.com/Allan-N/ASL-Asterisk.git](https://github.com/Allan-N/ASL-Asterisk.git) (my fork w/changes)**
* ASL-Nodes-Diff
	* **[https://github.com/AllStarLink/ASL-Nodes-Diff.git](https://github.com/AllStarLink/ASL-Nodes-Diff.git)**
* Allmon3 (optional)
	* **[https://github.com/AllStarLink/Allmon3.git](https://github.com/AllStarLink/Allmon3.git)**
* ASL-Supermon (optional)
	* [https://github.com/AllStarLink/ASL-Supermon.git](https://github.com/AllStarLink/ASL-Supermon.git) (main repo)
	* **[https://github.com/Allan-N/ASL-Supermon.git](https://github.com/Allan-N/ASL-Supermon.git) (my fork w/changes)**
* AllScan (optional)
	* **[https://github.com/davidgsd/AllScan.git](https://github.com/davidgsd/AllScan.git)**

### Initial Setup (Amazon Linux 2023)

```
# install git
sudo yum update
sudo yum install -y git
```

### Initial Setup (Debian 12.5 "bookworm")

```
# install git
sudo apt update
sudo apt upgrade -y
sudo apt install -y git
sudo apt autoremove -y
```

### Initial Setup (Ubuntu 22.04 LTS "jammy")

```
# install git
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
```

### Pre-installation notes (all OS's)

* If the above pre-installation commands (e.g. `sudo apt upgrade`) resulted in the kernel being updated then you should reboot the system before proceeding.

### Installation (all OS's)

```
# download this repository
git clone https://github.com/Allan-N/ASL-Install.git

# build and install AllStarLink
cd ASL-Install
./asl-install.sh
```

> The `asl-install.sh` script should present you with a menu of the steps needed to build, install, and configure a node.  Execute each step, in order, at least one time.

> When finished, the script will suggest that you reboot the system.  Unless you know that the changes you made would not affect the running configuration then please consider that to have been a **strong** suggestion.

#

> Note: to update your local copy of the repository you can use the `git pull` command

### Tidbits

Many of the AllStarLink/Asterisk commands (e.g. `asl-menu`, `astres.sh`, etc) are installed in the `/usr/sbin` directory.
One of the gotchas with [Debian] installs is that the default search PATH does not include this directory.
You can update your default path by updating the "~/.profile" file in your home directory. As an example, I have updated my file to look like :

```
...
# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# update PATH (WA3WCO)                                               <--- ADDED
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"  <--- ADDED
...
```

### Other useful commands

To update the hostname

```
hostnamectl
sudo hostnamectl set-hostname ASL-WA3WCO
```

To update the timezone

```
timedatectl
timedatectl list-timezones
sudo timedatectl set-timezone America/New_York
```

To check the networking subsystem

```
networkctl status
```

### Configuration options

To turn off the telemetry that announces nodes being connected/disconnected you can make the following changes to the `/etc/asterisk/rpt.conf` file :

```
Change "holdofftelem" from "0" to "1"
Change "telemdefault" from "1" to "2"
```

### ... and some of my favorite packages

* apt-file
	> APT package searching utility

	```
	sudo apt install -y apt-file
	```

* avahi-daemon
	> The Avahi mDNS/DNS-SD daemon (Apple's Zeroconf architecture (also known as "Bonjour")

	```
	sudo apt install -y avahi-daemon
	sudo cp /usr/share/doc/avahi-daemon/examples/ssh.service /etc/avahi/services
	```

* mlocate
	> find files by name, quickly (e.g. **locate asl-menu**)

	```
	sudo apt install -y mlocate
	sudo updatedb
	```

## Authors

* Allan Nathanson, WA3WCO




