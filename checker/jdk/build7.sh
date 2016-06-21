#!/bin/sh

# Builds JDK 7 jar for Checker Framework by inserting annotations into
# ct.sym.

# ensure CHECKERFRAMEWORK set
if [ -z "$CHECKERFRAMEWORK" ] ; then
    if [ -z "$CHECKER_FRAMEWORK" ] ; then
        export CHECKERFRAMEWORK=`(cd "$0/../.." && pwd)`
    else
        export CHECKERFRAMEWORK=${CHECKER_FRAMEWORK}
    fi
fi
[ $? -eq 0 ] || (echo "CHECKERFRAMEWORK not set; exiting" && exit 1)

# parameters derived from environment
# TOOLSJAR and CTSYM derived from JAVA_HOME, rest from CHECKERFRAMEWORK
JSR308="`cd $CHECKERFRAMEWORK/.. && pwd`"   # base directory
WORKDIR="${CHECKERFRAMEWORK}/checker/jdk"   # working directory
AJDK="${HOME}/sandbox/ajdk/jdk"             # annotated JDK
#AJDK="${JSR308}/annotated-jdk8u-jdk"        # annotated JDK
SRCDIR="${AJDK}/src/share/classes"
BINDIR="${WORKDIR}/build"
BOOTDIR="${WORKDIR}/bootstrap"              # initial build w/o processors
TOOLSJAR="${JAVA_HOME}/lib/tools.jar"
LT_BIN="${JSR308}/jsr308-langtools/build/classes"
LT_JAVAC="${JSR308}/jsr308-langtools/dist/bin/javac"
CF_BIN="${CHECKERFRAMEWORK}/checker/build"
CF_DIST="${CHECKERFRAMEWORK}/checker/dist"
CF_JAR="${CF_DIST}/checker.jar"
CF_JAVAC="java -Xmx512m -jar ${CF_JAR} -Xbootclasspath/p:${BOOTDIR}"
CP="${BINDIR}:${BOOTDIR}:${LT_BIN}:${TOOLSJAR}:${CF_BIN}:${CF_JAR}"
JFLAGS="-XDignore.symbol.file=true -Xmaxerrs 20000 -Xmaxwarns 20000\
 -source 8 -target 8 -encoding ascii -cp ${CP}"
PROCESSORS="fenum,formatter,guieffect,i18n,i18nformatter,interning,nullness,signature"
PFLAGS="-Anocheckjdk -Aignorejdkastub -AuseDefaultsForUncheckedCode=source\
 -AprintErrorStack -Awarns"
JAIFDIR="${WORKDIR}/jaifs"
SYMDIR="${WORKDIR}/sym"

set -o pipefail

# if present, JAVA_7_HOME overrides JAVA_HOME
[ -z "${JAVA_7_HOME}" ] || CTSYM="${JAVA_7_HOME}/lib/ct.sym"

# Explode (Java 7) ct.sym, extract annotations from jdk8.jar, insert
# extracted annotations into ct.sym classfiles, and repackage newly
# annotated classfiles as jdk7.jar.

rm -rf ${SYMDIR}
mkdir -p ${SYMDIR}
cd ${SYMDIR}

jar xf ${CTSYM}
cd ${WORKDIR}/sym/META-INF/sym/rt.jar  # yes, it's a directory

# annotate class files
rm -rf ${JAIFDIR}
for f in `find * -name '*\.class' -print` ; do
    B=`basename $f .class`
    D=`dirname $f`
    if [ -r ${BINDIR}/$f ] ; then
        echo "extract-annotations ${BINDIR}/$f"
        CLASSPATH=${CP} extract-annotations ${BINDIR}/$f
        JAIFS=`echo ${BINDIR}/$D/*.jaif`
        for g in ${JAIFS} ; do
            CLS="$D/`basename $g .jaif`.class"
            if [ -r "${CLS}" ] ; then
                echo "insert-annotations $CLS $g"
                insert-annotations "${CLS}" "$g"
            else
                echo ${CLS}: not found
            fi
        done

        mkdir -p ${JAIFDIR}/$D
        mv ${JAIFS} ${JAIFDIR}/$D
    fi
done

# construct annotated ct.sym
bash ${WORKDIR}/annotate-ct-sym.sh |& tee ${WORKDIR}/log/2.log

cd ${WORKDIR}
cp jdk.jar ${CF_DIST}/jdk7.jar
[ ${PRESERVE} -eq 0 ] || rm -rf sym
