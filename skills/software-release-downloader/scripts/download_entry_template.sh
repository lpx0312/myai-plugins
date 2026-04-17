#!/bin/bash

CURRENT_DIR=$(cd `dirname $0`; pwd)
#bash {SCRIPT_NAME}-downloader.sh -p http://192.168.0.225:7897 -t xxxx -V -d ${CURRENT_DIR}
bash {SCRIPT_NAME}-downloader.sh -p http://192.168.0.4:7890 -t ${GITHUB_TOKEN} -V -d ${CURRENT_DIR}
