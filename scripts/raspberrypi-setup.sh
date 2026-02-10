#!/bin/bash
#
# raspberrypi-setup.sh
# Setup Raspberry Pi for running Github self-hosted actions runner
#

set -e

echo "Preparing to install a self-hosted actions runner..."

curl -sSL https://get.docker.com | sh

echo "Now, go to the repository Settings / Actions / Runners to add a new self-hosted runner"
echo "Copy installation commands and paste them here to install and configure self-hosted runner."
