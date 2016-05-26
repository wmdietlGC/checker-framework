#!/bin/sh

# build annotated JDK 8

# ensure CHECKERFRAMEWORK set
if [ -z "$CHECKERFRAMEWORK" ] ; then
    if [ -z "$CHECKER_FRAMEWORK" ] ; then
        export CHECKERFRAMEWORK=`(cd "$0/../.." && pwd)`
    else
        export CHECKERFRAMEWORK=${CHECKER_FRAMEWORK}
    fi
fi
[ $? -eq 0 ] || (echo "CHECKERFRAMEWORK not set; exiting" && exit 1)

# Debugging
PRESERVE=1  # option to preserve intermediate files

# parameters derived from environment
# TOOLSJAR and CTSYM derived from JAVA_HOME, rest from CHECKERFRAMEWORK
JSR308="`cd $CHECKERFRAMEWORK/.. && pwd`"   # base directory
WORKDIR="${CHECKERFRAMEWORK}/checker/jdk"   # working directory
AJDK="${JSR308}/annotated-jdk8u-jdk"        # annotated JDK
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
CTSYM="${JAVA_HOME}/lib/ct.sym"
CP="${BINDIR}:${BOOTDIR}:${LT_BIN}:${TOOLSJAR}:${CF_BIN}:${CF_JAR}"
JFLAGS="-XDignore.symbol.file=true -Xmaxerrs 20000 -Xmaxwarns 20000\
 -source 8 -target 8 -encoding ascii -cp ${CP}"
PROCESSORS="fenum,formatter,guieffect,i18n,i18nformatter,interning,nullness,signature"
PFLAGS="-Anocheckjdk -Aignorejdkastub -AuseDefaultsForUncheckedCode=source\
 -AprintErrorStack -Awarns"

set -o pipefail

# This is called only when all source files successfully compiled.
# It does the following:
#  * explodes ct.sym
#  * for each annotated classfile:
#     * extracts its annotations
#     * inserts the annotations into the classfile's counterpart
#       in the ct.sym class directory
#  * repackages the resulting classfiles as jdk8.jar.
finish() {
    echo "building JAR"
    rm -rf ${WORKDIR}/sym ${WORKDIR}/jaifs
    mkdir -p ${WORKDIR}/sym
    cd ${WORKDIR}/sym
    # unjar ct.sym
    jar xf ${CTSYM}
    cd ${WORKDIR}/sym/META-INF/sym/rt.jar  # yes, it's a directory
    # annotate class files
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
                    insert-annotations "$CLS" "$g"
                else
                    echo ${CLS}: not found
                fi
            done
            # save JAIFs for analysis
            DEST=${WORKDIR}/jaifs/$D
            mkdir -p ${DEST}
            mv ${JAIFS} ${DEST}
        fi
    done
    # recreate jar
    rm -f ${WORKDIR}/jdk.jar
    jar cf ${WORKDIR}/jdk.jar *
    cp ${WORKDIR}/jdk.jar ${CF_DIST}/jdk8.jar
    cd ${WORKDIR}
    [ ${PRESERVE} -ne 0 ] || rm -rf sym
    return 0
}

rm -rf ${BOOTDIR} ${BINDIR}
mkdir -p ${BOOTDIR} ${BINDIR}
cd ${SRCDIR}

DIRS="`find com java javax jdk org sun \( -name META_INF -o -name dc\
 -o -name example -o -name jconsole -o -name pept -o -name snmp\
 -o -name security -o -name internal \) -prune -o -type d -print`"
SI_DIRS="`find com java javax jdk org sun \( -name META_INF -o -name dc\
 -o -name example -o -name jconsole -o -name pept -o -name snmp -prune \)\
 -o \( -name security -o -name internal \) -type d -print`"

if [ -z "${DIRS}" ] ; then
    echo "no annotated source files"
    exit 1
fi

echo "build bootstrap JDK"
rm -rf ${WORKDIR}/log
mkdir -p ${WORKDIR}/log
find ${DIRS} ${SI_DIRS} -maxdepth 1 -name '*\.java' -print | xargs\
 ${LT_JAVAC} -g -d ${BOOTDIR} ${JFLAGS} | tee ${WORKDIR}/0.log
[ $? -ne 0 ] && exit 1
grep -q 'not found' ${WORKDIR}/0.log
[ $? -eq 0 ] && exit 0
(cd ${BOOTDIR} && jar cf ../jdk.jar *)

# These packages are interdependent and cannot be compiled individually.
# Compile them all together.
echo "build internal and security packages"
find ${SI_DIRS} -maxdepth 1 -name '*\.java' -print | xargs\
 ${CF_JAVAC} -g -d ${BINDIR} ${JFLAGS} -processor ${PROCESSORS} ${PFLAGS}\
 | tee ${WORKDIR}/log/1.log
[ $? -ne 0 ] && exit 1

# Build one package at a time because building all of them together makes
# the compiler run out of memory.
echo "build one package at a time w/processors on"
for d in ${DIRS} ; do
    ls $d/*.java 2>/dev/null || continue
    echo :$d: `echo $d/*.java | wc -w` files
    ${CF_JAVAC} -g -d ${BINDIR} ${JFLAGS} -processor ${PROCESSORS} ${PFLAGS} \
            "$d"/*.java 2>&1 | tee ${WORKDIR}/log/`echo "$d" | tr / .`.log
done

# AGENDA keeps track of source files remaining to be processed
AGENDA=`cat ${WORKDIR}/log/* | grep -l 'Compilation unit: ' | awk '{print$3}' | sort -u`
if [ -z "${AGENDA}" ] ; then
    finish | tee ${WORKDIR}/log/2.log
    [ $? -eq 0 ] && exit 0
fi

echo "failed" | tee ${WORKDIR}/log/2.log
echo "${AGENDA}" | tee -a ${WORKDIR}/log/2.log
exit 1

