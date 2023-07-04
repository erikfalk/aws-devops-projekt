#!/bin/bash -ex
cd FlaskApp/
yum -y install python3-pip
pip install -r requirements.txt
yum -y install stress
export PHOTOS_BUCKET=employee-photo-bucket-ef-24241
export AWS_DEFAULT_REGION=eu-central-1
export DYNAMO_MODE=on
FLASK_APP=application.py /usr/local/bin/flask nohup run --host=0.0.0.0 --port=80 > log.txt 2>&1 &