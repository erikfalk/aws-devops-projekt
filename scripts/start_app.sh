#!/bin/bash -ex
cd FlaskApp/
yum -y install python3-pip
pip install -r requirements.txt
yum -y install stress
sudo systemctl daemon-reload
systemctl start flask-server.service 