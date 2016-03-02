

#set -e

VERSION="0.0.1"

SHARE_FOLDER="$HOME/docker-share"

MACHINE_NAME="default"

VERBOSE=1

MACHINE_MD5_LINUX_64=5558e5d7d003d337eacdc534c505dc5d
COMPOSE_MD5_LINUX_64=cb7f2d7f1a45bcff83cfd4669b1dcf53
DOCKER_MD5_LINUX_64=4583697764e695dd6d7f68d2834b5443

# Make a pseudo hashmap for legibility and because bash 3.x is the default on
# OSX and it doesn't support bash hash arrays.
distro=0
release=1
codename=2
arch=3
kernal=4
OS=([$distro]="" [$release]="" [$codename]="" [$arch]="")


show_help () {
  cat << EOF

UNIVERSAL DOCKER INSTALLER

version: $VERSION

Installs the docker suite of tools:
  - docker-engine (docker)
  - docker-machine
  - docker-compose

.. and dependencies
  - Virtualbox
  - docker-machine-nfs (speeds up docker-machine shares with nfs)

OSX
=====
  - Requires homebrew to be installed first.
  - Installs almost everything (including virtualbox) through homebrew
  - Installs docker-machine-nfs via curl


Linux (Defaults)
===============
  - Installs virtualbox via package manager when possible
  - Installs docker-engine via package manager when possible
  - Installs docker-machine binary via curl. See https://docs.docker.com/machine/install-machine/
  - Installs docker-compose via curl.


Ubuntu
-------
  - Installs virtualbox (if not exists) through apt-get by adding virtualbox to apt sources.
  - Installs docker-engine through apt-get by adding docker to apt sources.

ArchLinux
---------
  - [todo]

EOF
}

get_os() {

  if [ ! "$(which uname)" ]; then
    echo "WINDOWS NOT SUPPORTED YET"
    exit 1
  fi

  UNAME=$(uname)

  # We're on OSX
  if [ $UNAME == "Darwin" ]; then
    OS[$distro]="OSX"
    OS[$release]="$(sw_vers -productVersion || false)"
    # Not worth mapping OSX codenames I think and there isn't an easy cli command
    # For codename on OSX.
    OS[$codename]=""
    OS[$arch]="$(uname -m)"
    OS[$kernal]="$(uname -r)"

  # UBUNTU and ARCH has lsb_release
  elif [ $(which lsb_release) ]; then
    OS[$distro]="$(lsb_release --id -s || false)"
    # On ARCH, this can be 'rolling' instead of a version number
    OS[$release]="$(lsb_release --release -s || false)"
    OS[$codename]="$(lsb_release --codename -s || false)"
    OS[$arch]="$(uname -m)"
    OS[$kernal]="$(uname -r)"

  else
    echo "This OS isn't supported yet"
    exit 1
  fi
}

get_rc_file() {
  if [ $SHELL == "/bin/zsh" ] || [ $SHELL == "/usr/bin/zsh" ]; then
    RC_FILE="$HOME/.zshrc"
  elif [ $SHELL == "/bin/bash" ] || [ $SHELL == "/bin/bash" ]; then
    RC_FILE="$HOME/.bashrc"
  else
    "Error: Sorry, we don't support the $SHELL shell."
  fi
}

checksum() {
  echo $1 $2 | md5sum -c -
}

cmd() {
  if [ $VERBOSE ]; then
    echo "COMMAND==> ${@:2}"
  fi
  printf "> $1 .. "
  OUTPUT=`eval ${@:2}`
  result=$?

  if [ $result -eq 0 ]; then
    echo "success"
    if [ $VERBOSE ]; then
      #echo "OUTPUT===> $OUTPUT"
      echo ""
    fi
  else
    echo "fail"
    if [ $VERBOSE ]; then
      echo "OUTPUT===> $OUTPUT"
    fi
    exit 1
  fi
}


install_docker_engine() {

  # Use a specific shared folder instead of just /Users or /home so that nfs mounts don't conflict.
  # This is most important when running other vitualbox instances setup with nfs.
  if [ -d "$SHARE_FOLDER" ]; then
    echo "Error: The share folder, '$SHARE_FOLDER' already exists. Please backup your data and remove the folder if you want to start over."
    exit 1
  else
    cmd "Creating the shared folder at $SHARE_FOLDER" mkdir $SHARE_FOLDER
  fi

  if [ ${OS[$distro]} == "Darwin" ]; then
    # Assume homebrew is a requirement for now
    if [ ! "$(which brew)" ]; then
      echo "Error: It looks like homebrew isn't installed. Please install that first."
      exit 1
    fi
    cmd "Updating Homebrew" brew update

    if [ -z "$(brew cask update)" ]; then
      echo "Error: It looks like homebrew cask isn't installed. As of Dec 2015, it should come with homebrew. Try 'brew update'"
    fi

    cmd "Installing the latest virtualbox" brew update
    cmd "Installing docker-engine" brew install docker
    cmd "Installing docker-machine" brew install docker-machine
    cmd "Installing docker-machine" brew install docker-machine
    cmd "Installing docker-machine-nfs" '
      curl -s https://raw.githubusercontent.com/adlogix/docker-machine-nfs/master/docker-machine-nfs.sh |
      sudo tee /usr/local/bin/docker-machine-nfs > /dev/null && sudo chmod +x /usr/local/bin/docker-machine-nfs'


    cmd "Creating a default docker-machine" docker-machine create --driver virtualbox $MACHINE_NAME
    cmd "Setting up the default docker-machine with NFS" docker-machine-nfs $MACHINE_NAME
    cmd "Starting docker-machine '$MACHINE_NAME'" docker-machine start $MACHINE_NAME
    cmd "Adding machine environment variables to $RC_FILE" 'docker-machine env $MACHINE_NAME | grep export >> $RC_FILE'
    cmd "Sourcing variables in '$RC_FILE'" source $RC_FILE

    cmd "Testing share folder" 'touch $SHARE_DIR/test-file && docker-machine ssh default ls /Users/$USER/$SHARE_DIR/test-file'
  fi

  if [ ${OS[$distro]} == "Ubuntu" ]; then
    cmd "Adding virtualbox to apt sources" 'echo "deb http://download.virtualbox.org/virtualbox/debian ${OS[$codename]} contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list > /dev/null && wget -q https://www.virtualbox.org/download/oracle_vbox.asc -O- | sudo apt-key add - && sudo apt-get update'
    cmd "Installing virtualbox" sudo apt-get install virtualbox-5.0

    cmd "Adding docker to apt sources" 'sudo apt-get install apt-transport-https ca-certificates && sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D && echo "deb https://apt.dockerproject.org/repo ubuntu-${OS[$codename]} main" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && sudo apt-get update'

    cmd "Remove legacy lxc-docker if it exists" sudo apt-get purge lxc-docker
    cmd "Install linux-image-extra" sudo apt-get install linux-image-extra-$(uname -r)
    if [[ ${OS[$release]} == "12"* ||  ${OS[$release]} == "14"* ]]; then
      cmd "Install apparmor on Ubunu 12.04 or 14.04" sudo apt-get install apparmor
    fi

    cmd "Installing docker-engine" 'checksum $DOCKER_MD5_LINUX_64 /usr/bin/docker || sudo apt-get install docker-engine && checksum $DOCKER_MD5_LINUX_64 /usr/bin/docker'
    cmd "Installing docker-machine" 'checksum $MACHINE_MD5_LINUX_64 /usr/local/bin/docker-machine || sudo wget -q https://github.com/docker/machine/releases/download/v0.6.0/docker-machine-`uname -s`-`uname -m` -O /usr/local/bin/docker-machine && sudo chmod 755 /usr/local/bin/docker-machine && checksum $MACHINE_MD5_LINUX_64 /usr/local/bin/docker-machine'
    cmd "Installing docker-compose" 'checksum $COMPOSE_MD5_LINUX_64 /usr/local/bin/docker-compose || sudo wget -q https://github.com/docker/compose/releases/download/1.6.0/docker-compose-`uname -s`-`uname -m` -O /usr/local/bin/docker-compose && sudo chmod 755 /usr/local/bin/docker-compose &&  checksum $COMPOSE_MD5_LINUX_64 /usr/local/bin/docker-compose'
    # Note that we needed to modify the docker-machine-nfs script to work with linux. So load the custom version.
    # See https://github.com/adlogix/docker-machine-nfs/pull/51
    cmd "Installing docker-machine-nfs (custom version)" '
      sudo wget -q https://raw.githubusercontent.com/devinci-code/docker-machine-nfs/dev-50-support-linux/docker-machine-nfs.sh -O /usr/local/bin/docker-machine-nfs && sudo chmod 755 /usr/local/bin/docker-machine-nfs'

    cmd "Creating a default docker-machine" docker-machine create --driver virtualbox $MACHINE_NAME
    cmd "Setting up the default docker-machine with NFS" docker-machine-nfs $MACHINE_NAME --nfs-config='\(rw,sync,no_root_squash,no_subtree_check\)' --shared-folder=$SHARE_DIR --force
    cmd "Starting docker-machine '$MACHINE_NAME'" docker-machine start $MACHINE_NAME
    cmd "Adding machine environment variables to $RC_FILE" 'docker-machine env $MACHINE_NAME | grep export >> $RC_FILE'
    cmd "Sourcing variables in '$RC_FILE'" source $RC_FILE

    cmd "Testing share folder" 'touch $SHARE_DIR/test-file && docker-machine ssh default ls $SHARE_DIR/test-file'
  fi
  if [ ${OS[$distro]} == "Arch" ]; then
    if [ `pacman -Q yaourt 2> /dev/null|wc -l` -lt 1 ]
    then
      echo "Error: Yaourt is required to install docker-machine. Aborting installation."
      exit 1
    fi
    if [ `pacman -Q virtualbox docker docker-machine 2> /dev/null|wc -l` -gt 0 ]
    then
      echo "Error: Existing Virtualbox and/or Docker installation detected. Reinstalling Virtualbox, docker and docker-machine."
    fi
    cmd " Installing virtualbox" yaourt -S virtualbox virtualbox-guest-dkms virtualbox-guest-iso virtualbox-guest-modules virtualbox-guest-utils virtualbox-host-dkms virtualbox-host-modules
    if [ `lsmod|cut -d ' ' -f1|grep -E '(vboxdrv|vboxpci|vboxnetflt|vboxnetadp)'|wc -l` -gt 0 ]
    then
      echo "Error: Existing Virtualbox kernel modules detected. Skipping Virtualbox module loading and enabling modules on system startup."
    else
      cmd "Setting up Virtualbox modules" sudo /sbin/rcvboxdrv setup
      cmd "Enabling Virtualbox modules on system startup: /etc/modules-load.d/virtualbox.conf" 'sudo sh -c "echo -e \"vboxnetadp\nvboxnetflt\nvboxpci\nvboxdrv\" > /etc/modules-load.d/virtualbox.conf"'
    fi
    cmd "Installing docker" yaourt -S docker docker-compose docker-machine

    # Note that we needed to modify the docker-machine-nfs script to work with linux. So load the custom version.
    # See https://github.com/adlogix/docker-machine-nfs/pull/51
    # TODO: add nfs support

    cmd "Creating a default docker-machine" docker-machine create --driver virtualbox $MACHINE_NAME
    # TODO: setup the default machine with nfs
    DEFAULT_SOURCE="$HOME/.default.docker-machine"
    cmd "Adding machine environment variables to $DEFAULT_SOURCE" 'docker-machine env $MACHINE_NAME | grep -v "^#" > $DEFAULT_SOURCE'
    cmd "Sourcing variables in $DEFAULT_SOURCE" source $DEFAULT_SOURCE
    cmd "Sourcing $DEFAULT_SOURCE in $RC_FILE" 'echo "source $DEFAULT_SOURCE" >> $RC_FILE'
  fi
}

## MAIN ##

show_help
get_os
get_rc_file
install_docker_engine
