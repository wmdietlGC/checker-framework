#!/bin/sh

# Builds JDK 7 jar for Checker Framework by inserting annotations into
# ct.sym.

# ensure CHECKERFRAMEWORK set
[ ! -z "$CHECKERFRAMEWORK" ] ||\
 (echo "CHECKERFRAMEWORK not set; exiting" && exit 1)

set -o pipefail
. env

JAIFDIR="${SCRIPTDIR}/jaifs"
PRESERVE=1  # option to preserve intermediate files

# if present, JAVA_7_HOME overrides JAVA_HOME
[ -z "${JAVA_7_HOME}" ] || CTSYM="${JAVA_7_HOME}/lib/ct.sym"

# construct annotated ct.sym
cd ${SCRIPTDIR}
sh ./annotate-ct-sym.sh
cp jdk.jar ${CF_DIST}/jdk7.jar
[ ${PRESERVE} -eq 0 ] || rm -rf sym
