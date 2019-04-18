#!/bin/bash
# uncomment to debug the script
# set -x
#CF_TRACE=true
# copy the script below into your app code repo (e.g. ./scripts/cf_rolling_deploy.sh) and 'source' it from your pipeline job
#    source ./scripts/cf_rolling_deploy.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cf_rolling_deploy.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/cf_rolling_deploy.sh

# Performs a rolling deployment of a CF app, by pushing the new app on the same route as the old
# app. The old app still kept running in parallel to handle incoming traffic while the new app is started.
# The old app is renamed to avoid the new app to override it. Once the new app is established,
# the old app is simply discarded.
# For a more progressive rollout, please see the blue/green deployment script at 
# https://raw.githubusercontent.com/open-toolchain/commons/master/scripts
# This script should be run in a CF deploy job. It will export the new APP_URL

# Push app
if ! cf app $CF_APP; then  
  cf push $CF_APP
else
  OLD_CF_APP=${CF_APP}-OLD-$(date +"%s")
  rollback() {
    set +e  
    if cf app $OLD_CF_APP; then
      cf logs $CF_APP --recent
      cf delete $CF_APP -f
      cf rename $OLD_CF_APP $CF_APP
    fi
    exit 1
  }
  set -e
  trap rollback ERR
  cf rename $CF_APP $OLD_CF_APP
  cf push $CF_APP
  cf delete $OLD_CF_APP -f
fi
# Export app name and URL for use in later Pipeline jobs
export CF_APP_NAME="$CF_APP"
export APP_URL=http://$(cf app $CF_APP_NAME | grep -e urls: -e routes: | awk '{print $2}')
# View logs
#cf logs "${CF_APP}" --recent
