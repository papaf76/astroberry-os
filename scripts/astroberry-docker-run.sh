#!/bin/bash
#
# astroberry-docker-run.sh
# Start astroberry builder docker image
#

docker run --privileged --rm -it -v /dev:/dev -v .:/work  ghcr.io/astroberry-official/astroberry-os/debian-trixie
