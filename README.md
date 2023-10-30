# ASL-Install

## This project is [currently] focused on the steps needed to build, install, and configure an AllStarLink node running on a virtual machine [VM] in the cloud.

## Target Operating System(s)

This package has been tested on :

* Amazon Linux 2023
* Debian 12.2 "bookworm"
* Ubuntu 22.04 LTS "jammy"

### Packages installed

* 	ASL-DAHDI
	* **[https://github.com/AllStarLink/ASL-DAHDI.git]()**
*  ASL-Asterisk
	* [https://github.com/AllStarLink/ASL-Asterisk]() (main repo)
	* **[https://github.com/Allan-N/ASL-Asterisk.git]() (my fork w/changes)**
*  ASL-Nodes-Diff
	* **[https://github.com/AllStarLink/ASL-Nodes-Diff.git]()**
*	ASL-Supermon
	* [https://github.com/AllStarLink/ASL-Supermon.git]() (main repo)
	* **[https://github.com/Allan-N/ASL-Supermon.git]() (my fork w/changes)**
*	AllScan
	* [https://github.com/davidgsd/AllScan.git]() (main repo)
	* **[https://github.com/Allan-N/AllScan.git]() (my fork w/changes)**

### Initial Setup (Amazon Linux 2023)

```
# install git
sudo yum update
sudo yum install -y git
```

### Initial Setup (Debian 12.2 "bookworm")

```
# install git
sudo apt update
sudo apt upgrade -y
sudo apt install -y git
```

### Initial Setup (Ubuntu 22.04 LTS "jammy")

```
# install git
sudo apt update
sudo apt upgrade -y
```

> Note: if the `sudo apt upgrade` command resulted in the kernel being updated then you should reboot the system before proceeding.


### Installation (all OS's)
```
# download this repository
git clone https://github.com/Allan-N/ASL-Install.git

# build and install AllStarLink
cd ASL-Install
./asl-install.sh
```

> The `ASL-install` script should present you with a menu of the steps needed to build, install, and configure a node.  Execute each step, in order, at least one time.

> When finished, the script will suggest that you reboot the system.  Unless you know that the changes you made would not affect the running configuration then please consider that to have been a **strong** suggestion.

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

### Configuration options

To turn off the telemetry that announces nodes being connected/disconnected you can make the following changes to the `/etc/asterisk/rpt.conf` file :

```
Change "holdofftelem" from "0" to "1"
Change "telemdefault" from "1" to "2"
```

## Authors

* Allan Nathanson, WA3WCO




