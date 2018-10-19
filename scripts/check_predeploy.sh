#!/bin/bash
echo "script renamed into check_predeploy_helm.sh"
set -x
source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_predeploy_helm.sh")