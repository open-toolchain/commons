# Common material for toolchains

This repo is collecting a range of common scripts that can be leveraged in toolchains, pipelines.
For instance, you can use one of the shell scripts in your own toolchains in different ways.

1. Copy a script content in one of your pipeline job script.

2. Fetch a script from the commons location, and source it from your pipeline job.
```
    `#!/bin/bash
    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_helm")`
```
3. Copy a script inside your application code (in a `/scripts` subfolder), and source it from your pipeline job.
```
    `#!/bin/bash
    source ./scripts/deploy_helm`
```
You can even combine the two... use local scripts, or defer to remote one...    
```   #!/bin/bash
      # use script from app source control, or default to template script
      # use source command to run script to ensure env variables are set in current shell
      SCRIPT_FILE="scripts/build_image.sh"
      SCRIPT_URL="https://raw.githubusercontent.com/open-toolchain/simple-helm-toolchain/master/${SCRIPT_FILE}"
      if [ ! -f  ${SCRIPT_FILE} ]; then
        echo -e "No script found at ./${SCRIPT_FILE}, defaulting to ${SCRIPT_URL}"
        source <(curl -sSL ${SCRIPT_URL})
      else
        source "${SCRIPT_FILE}"
      fi`
```
### Recommendations:
1. Initially try to understand the script behavior, by inserting `set -x` at the top of the script, you'll get better insight into the script command executions.
2. Prefer `source` over `sh` command to run a script, as it then runs in the parent shell environment. Thus allowing to export environment variables that can be consumed in subsequent jobs in the same stage.

