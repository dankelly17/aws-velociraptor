#!/bin/bash

#############################
# MAKE SURE JQ IS INSTALLED #
#############################

# this will take long standing VR servers and clients
# move existing binaries and configs to a backup dir
# download the most up to date VR clients
# create the new server debian package, clients, and configs
# then run the new servers

# requires jq to download most recent VR packages
if [[ $(dpkg -s jq) =~ .*Status.* ]];
then
        echo "jq already installed";
else
        sudo apt update -y && sudo apt install jq -y;
fi

# package install
sleep 10

# make directory for current files/configs to serve as a backup
mkdir -p /opt/velociraptor/backup/clients
mkdir -p /opt/velociraptor/backup/installers

# make dir to download new files
mkdir -p /opt/velociraptor/working/clients
mkdir -p /opt/velociraptor/working/installers

# copy all existing client and server packages to the new directory
echo "backing up files"
cp /opt/velociraptor/clients/* /opt/velociraptor/backup/clients
cp /opt/velociraptor/installers/* /opt/velociraptor/backup/installers

# copy over the server packages
echo "backing up server packages"
cp /opt/velociraptor/veloc* /opt/velociraptor/backup

# copy over the configs
echo "backing up packages"
cp /opt/velociraptor/client.config.yaml /opt/velociraptor/backup/client.config.yaml
cp /opt/velociraptor/server.config.yaml /opt/velociraptor/backup/server.config.yaml

# copy over server config to working dir
echo "transferring server config"
cp /opt/velociraptor/server.config.yaml /opt/velociraptor/working/

# download the new clients to the "installers" directory
wget -O "/opt/velociraptor/working/installers/vr_linux" $(curl -s https://api.github.com/repos/velocidex/velociraptor/releases/latest | jq -r '[.assets | sort_by(.created_at) | reverse | .[] | .browser_download_url | select(test("linux-amd64$"))][0]')
wget -O "/opt/velociraptor/working/installers/vr_windows.exe" $(curl -s https://api.github.com/repos/velocidex/velociraptor/releases/latest | jq -r '[.assets | sort_by(.created_at) | reverse | .[] | .browser_download_url | select(test("windows-amd64.exe$"))][0]')
wget -O "/opt/velociraptor/working/installers/vr_msi.msi" $(curl -s https://api.github.com/repos/velocidex/velociraptor/releases/latest | jq -r '[.assets | sort_by(.created_at) | reverse | .[] | .browser_download_url | select(test("windows-amd64.msi$"))][0]')
wget -O "/opt/velociraptor/working/installers/vr_darwin" $(curl -s https://api.github.com/repos/velocidex/velociraptor/releases/latest | jq -r '[.assets | sort_by(.created_at) | reverse | .[] | .browser_download_url | select(test("darwin-amd64$"))][0]')

# copy linux to velociraptor working root folder
cp /opt/velociraptor/working/installers/vr_linux /opt/velociraptor/working/velociraptor
chmod +x /opt/velociraptor/working/velociraptor

# sleeping 5 seconds
sleep 5

# create the new debian server pack
echo "creating debian server pack"
cd /opt/velociraptor/working
/opt/velociraptor/working/velociraptor --config /opt/velociraptor/working/server.config.yaml debian server
chmod +x /opt/velociraptor/working/velociraptor_*.deb

# remove the current package and install the new package
echo "installing new package"
rm -rf /opt/velociraptor/velociraptor_*.deb
mv /opt/velociraptor/working/velociraptor /opt/velociraptor/velociraptor
mv /opt/velociraptor/working/velociraptor_*.deb /opt/velociraptor
dpkg -i /opt/velociraptor/velociraptor_*.deb

# sleep after installing package
sleep 10

# have VR own the /opt/velociraptor dir and subdirs
chown velociraptor -R /opt/velociraptor/*

# create the new client configs as the velociraptor user
# can also remove this since it will change the hashes and EDR/AV might flag the windows binaries when trying to do things like search/parse the $MFT
echo "repacking configs"
sudo -u velociraptor velociraptor config client > /opt/velociraptor/working/client.config.yaml
sudo -u velociraptor velociraptor config repack --msi /opt/velociraptor/working/installers/vr_msi.msi /opt/velociraptor/working/client.config.yaml /opt/velociraptor/working/clients/velociraptor.msi
sudo -u velociraptor velociraptor config repack --exe /opt/velociraptor/working/installers/vr_windows.exe /opt/velociraptor/working/client.config.yaml /opt/velociraptor/working/clients/velociraptor.exe
sudo -u velociraptor velociraptor config repack --exe /opt/velociraptor/working/installers/vr_darwin /opt/velociraptor/working/client.config.yaml /opt/velociraptor/working/clients/velociraptor_darwin
sudo -u velociraptor velociraptor config repack --exe /opt/velociraptor/working/installers/vr_linux /opt/velociraptor/working/client.config.yaml /opt/velociraptor/working/clients/velociraptor_linux
sudo -u velociraptor velociraptor --config /opt/velociraptor/working/client.config.yaml debian client --output /opt/velociraptor/working/clients/vr_linux.deb

# upload artifacts to s3 or whatever central repo for clients to pull down or sysadmins to deploy