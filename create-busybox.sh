#!/bin/sh
CONTAINER=/container

mkdir -p ${CONTAINER}/{1,2}
sudo chmod a+w ${CONTAINER}/{1,2}
cd ${CONTAINER}
sudo busybox --install 1; sudo busybox --install 2
mkdir {1,2}/proc
