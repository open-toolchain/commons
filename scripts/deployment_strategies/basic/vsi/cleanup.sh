#!/bin/bash
RESTOREFILE=${WORKDIR}/previous_build.info

echo "WORKDIR ${WORKDIR}"
echo "RESTOREFILE ${RESTOREFILE}"

echo "Begin creating the cleanup script to be executed on the Virtual Server Instance"

if [ -f "${RESTOREFILE}" ]; then
    RESTOREDIR=$(head -n 1 ${RESTOREFILE})
    echo "RESTOREDIR is ${RESTOREDIR} "
    PREVIOUSRESTOREDIRFILE=${RESTOREDIR}/previous_build.info
    echo "PREVIOUSRESTOREDIRFILE is ${PREVIOUSRESTOREDIRFILE}"
    echo "BUILDDIR is ${BUILDDIR}"
    PREVIOUSRESTOREDIR=$(head -n 1 ${PREVIOUSRESTOREDIRFILE})
    if [[ "${BUILDDIR}" == "${PREVIOUSRESTOREDIR}" ]] ; then
       echo "pre-previous build does not exists..."
    elif [ -f "${PREVIOUSRESTOREDIRFILE}" ]; then
        echo "Performing Cleanup of pre-previous directory.....${PREVIOUSRESTOREDIR}"
        rm -rf ${PREVIOUSRESTOREDIR}
        echo "Cleanup Completed..."
    else
        echo "pre-previous build does not exists..."
        echo "Cleanup Completed..."
    fi
else
    echo "Previous build info file does not exits..."
    echo "Cleanup Completed..."
fi
