#!/bin/bash -ex
cp FlaskApp/scripts/flask-server.service /etc/systemd/system
sudo systemctl daemon-reload