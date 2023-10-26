# ASL-Install

## This project is [currently] focused on the steps needed to build, install, and configure an AllStarLink node running on a virtual machine [VM] in the cloud.

## Target Operating System(s)

This package has been tested on :

* Amazon Linux 2023
* Debian Linux "bookworm"

### Packages installed

* 	ASL-DAHDI
	* **[https://github.com/AllStarLink/ASL-DAHDI.git]()**
*  ASL-Asterisk
	* [https://github.com/AllStarLink/ASL-Asterisk]() (main repo)
	* **[https://github.com/Allan-N/ASL-Asterisk.git]() (fork w/changes)**
*  ASL-Nodes-Diff
	* **[https://github.com/AllStarLink/ASL-Nodes-Diff.git]()**
*	ASL-Supermon
	* [https://github.com/AllStarLink/ASL-Supermon.git]() (main repo)
	* **[https://github.com/Allan-N/ASL-Supermon.git]() (fork w/changes)**
*	AllScan
	* [https://github.com/davidgsd/AllScan.git]() (main repo)
	* **[https://github.com/Allan-N/AllScan.git]() (fork w/changes)**

### Initial Setup (Amazon Linux 2023)

```
# install git
sudo yum update
sudo yum install -y git

# download this repository
git clone https://github.com/Allan-N/ASL-Install.git
```

### Initial Setup (Debian Linux "bookworm")

```
# install git
sudo apt update
sudo apt upgrade
sudo apt install -y git

# download this repository
git clone https://github.com/Allan-N/ASL-Install.git
```

### Installation (all OS's)
```
./asl-install.sh
```

This script should present you with a menu of the steps needed to build, install, and configure a node.  Execute each step, in order, at least one time.

## Authors

* Allan Nathanson, WA3WCO




