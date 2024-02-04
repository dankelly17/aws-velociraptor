#!/bin/bash
# This script will spin up a quick VR EC2 with default SSL certs and use the ec2 hostname for the server name
# Read the comments and commands and feel free to modify.

# Tested and ran this on an ubuntu ec2
# Have not tested this as a user-data script but should work. Otherwise can spin up the EC2 and let it run
# Feel free to just apt install jq and comment out the lines. Otherwise, just run it

# update and upgrade, install jq if not exists
if [[ $(dpkg -s jq) =~ .*Status.* ]];
then
    echo "jq already installed";
else
    sudo apt update -y && sudo apt install jq -y;
fi

sleep 10

################
# Velociraptor #
################

# make necessary directories
mkdir /opt/velociraptor
for i in installers clients; do mkdir -p /opt/velociraptor/$i; done &&

# download the clients to the "installers" directory
wget -O "/opt/velociraptor/installers/vr_linux" $(curl -s https://api.github.com/repos/velocidex/velociraptor/releases/latest | jq -r '[.assets | sort_by(.created_at) | reverse | .[] | .browser_download_url | select(test("linux-amd64$"))][0]')
wget -O "/opt/velociraptor/installers/vr_windows.exe" $(curl -s https://api.github.com/repos/velocidex/velociraptor/releases/latest | jq -r '[.assets | sort_by(.created_at) | reverse | .[] | .browser_download_url | select(test("windows-amd64.exe$"))][0]')
wget -O "/opt/velociraptor/installers/vr_msi.msi" $(curl -s https://api.github.com/repos/velocidex/velociraptor/releases/latest | jq -r '[.assets | sort_by(.created_at) | reverse | .[] | .browser_download_url | select(test("windows-amd64.msi$"))][0]')
wget -O "/opt/velociraptor/installers/vr_darwin" $(curl -s https://api.github.com/repos/velocidex/velociraptor/releases/latest | jq -r '[.assets | sort_by(.created_at) | reverse | .[] | .browser_download_url | select(test("darwin-amd64$"))][0]')

# copy linux to velociraptor root folder
cp /opt/velociraptor/installers/vr_linux /opt/velociraptor/velociraptor
chmod +x /opt/velociraptor/velociraptor

# I recommend using this for an EC2 deployment. If you do, uncomment these lines
# Get the public dns name
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` 
URL=`curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/public-hostname`

# REMEMBER to also add security groups to the gui, client, and api ports
# in an engagement, get the company's IP egress ranges (if possible, with remote work, this is difficult. Not the end of the world to leave client ports open since client <> server use PKI)
# for the gui, restrict to your security teams corp/VPN ranges/security team only ip ranges
# client port is 443 for client comms to blend in to normal internet traffic but can easily change it. also no need to customer sysadmin to open up port 8000. only slows down engagements
/opt/velociraptor/velociraptor config generate >> /opt/velociraptor/server.config.yaml --merge '{"Client":{"server_urls":["https://'$URL':443/"],"use_self_signed_ssl":true},"API":{"bind_address":"0.0.0.0", "bind_port":8000},"Frontend":{"hostname":"'$URL'", "bind_port":8443},"GUI":{"bind_address":"0.0.0.0", "bind_port":8443, "public_url":"https://'$URL'"}}' 

# create the server config - this section is a bit more customizable
# if you have your own domains, certs, or want to use oauth SSO for login
# Refer to this for more info: https://docs.velociraptor.app/docs/deployment/cloud/
# also if you do not use oauth, feel free to remove that section entirely. You can create user accounts and passwords instead
# you also dont need an api service. And can delete that section if you dont plan to use it
#/opt/velociraptor/velociraptor config generate >> /opt/velociraptor/server.config.yaml --merge '{"Client":{"server_urls":["https://<client_url>:<client_port>/"],"use_self_signed_ssl":false},"API":{"bind_address":"0.0.0.0", "bind_port":<api_port>},"GUI":{"bind_address":"0.0.0.0", "bind_port":<gui_port>, "public_url":"<gui_url>", "authenticator":{"type":"multi","sub_authenticators":[{"type":"oidc","oidc_issuer":"<oauth_url>","oauth_client_id":"<oauth_client_id>","oauth_client_secret":"<oauth_secret>","oidc_name":"<oauth_name>","avatar":"<default image icon for oauth login>"}]}},"Frontend":{"hostname":"<gui_url>", "bind_port":<gui_port>}}'

# create the VR server binary package
cd /opt/velociraptor && /opt/velociraptor/velociraptor --config /opt/velociraptor/server.config.yaml debian server

# start the VR server
chmod +x /opt/velociraptor/velociraptor_*.deb
dpkg -i /opt/velociraptor/velociraptor_*.deb

# sleep for a few seconds
sleep 5

# create the client config. After installing the VR service, do everything as the velociraptor user
sudo -u velociraptor velociraptor config client >> /opt/velociraptor/client.config.yaml

# let the velociraptor user own the /opt/velociraptor/clients dir (as it properly should and not the sudo dir)
chown velociraptor -R /opt/velociraptor/*

# repack configs into the clients
# this will effectively change the client hash and cause some EDR tools to quarantine this (Windows especially)
# so feel free to comment these lines out if you do not want the hash to change and would rather use the hash instead
# additionally, you can digitally sign the binaries and incorporate that script into your automation
sudo -u velociraptor velociraptor config repack --msi /opt/velociraptor/installers/vr_msi.msi /opt/velociraptor/client.config.yaml /opt/velociraptor/clients/velociraptor.msi
sudo -u velociraptor velociraptor config repack --exe /opt/velociraptor/installers/vr_windows.exe /opt/velociraptor/client.config.yaml /opt/velociraptor/clients/velociraptor.exe
sudo -u velociraptor velociraptor config repack --exe /opt/velociraptor/installers/vr_darwin /opt/velociraptor/client.config.yaml /opt/velociraptor/clients/velociraptor_darwin
sudo -u velociraptor velociraptor config repack --exe /opt/velociraptor/installers/vr_linux /opt/velociraptor/client.config.yaml /opt/velociraptor/clients/velociraptor_linux

# create persistent debian client
sudo -u velociraptor velociraptor --config /opt/velociraptor/client.config.yaml debian client --output /opt/velociraptor/clients/vr_linux.deb

# upload the files to s3 or whatever central repo you want. Can have clients pull down directly or give to sysadmins to deploy
# make sure to sudo apt update -y && sudo apt install awscli -y if using s3
# aws s3 cp /opt/velociraptor/clients/ s3://<s3_url>/clients/ --recursive

# create users. refer to rbac model: https://docs.velociraptor.app/blog/2020/2020-03-29-velociraptors-acl-model-7f497575daee/
sudo -u velociraptor velociraptor user add <username> --role <role1,role2> <password>
sudo -u velociraptor velociraptor acl grant <username> --role <role1,role2> 

#IF you are using oauth for logins, this is the command you run. Sometimes the username is not an email
# then the user logs in with oauth and forwards to the VR server
#sudo -u velociraptor velociraptor user add <username@domain.com> --role <role1,role2>