This repo is collecting a range of common materials that can be leverage in toolchains, pipelines.

For instance, you can use one of the shell scripts in your own toolchains in different ways.

1. Copy a script content in one of your pipeline job script.

2. Fetch a script from the commons location, and source it from your pipeline job.

    #!/bin/bash
    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/deploy_helm")

3. Copy a script inside your application code (in a /scripts subfolder), and source it from your pipeline job.

    #!/bin/bash
    source ./scripts/deploy_helm

Recommendations:
1. Initially try to understand the script behavior, by inserting 'set -x' at the top of the script, you'll get more insights into the script command executions.
2. Prefer 'source' over 'sh' to run a script, as it then runs in the parent shell environment. Thus allowing to export environment variables that can be consumed in subsequent jobs in the same stage.