#!/bin/bash -ex
yum update
wget https://github.com/erikfalk/aws-devops-projekt/archive/refs/heads/main.zip
unzip main.zip
cp -r aws-devops-projekt-main/FlaskApp/ /FlaskApp
cp aws-devops-projekt-main/scripts/flask-server.service /etc/systemd/system
rm -f main.zip
# rm -rf aws-devops-projekt-main/
cd FlaskApp/
yum -y install python3-pip
pip install -r requirements.txt
yum -y install stress
cd /
yum install ruby
wget https://aws-codedeploy-eu-central-1.s3.eu-central-1.amazonaws.com/latest/install
chmod +x ./install
./install auto
cd FlaskApp/
sudo systemctl daemon-reload
systemctl start flask-server.service 
