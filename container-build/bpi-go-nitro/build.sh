#!/bin/bash

set -e

PROJ_NAME="go-nitro"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

env
source ${BPI_CONTAINER_BASE_DIR}/build-base.sh

cd $BPI_REPO_BASE_DIR/$PROJ_NAME
make docker/nitro/build

cd $SCRIPT_DIR
docker build -t ${BPI_DEFAULT_CONTAINER_IMAGE_TAG} .