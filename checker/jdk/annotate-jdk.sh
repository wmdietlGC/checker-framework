#!/bin/sh

# annotates the JDK

# JDK to be annotated
JDK=$HOME/sandbox/jdk8u/jdk

# parameters derived from environment
AFU="${CHECKERFRAMEWORK}/../annotation-tools"
AFUJAR="${AFUJAR}/annotation-file-utilities/annotation-file-utilities.jar"
CFJAR="${CHECKERFRAMEWORK}/checker/dist/checker.jar"
CP=".:${CFJAR}:${AFUJAR}:${CLASSPATH}"

# temp directory
TMPDIR="/tmp/$$"

# return value
RET=0

#[ $# -ge 1 ] && TMPDIR=`realpath $1`
[ -z "`ls`" ] && echo "no files" 1>&2 && exit 1


# Stage 1: extract JAIFs from nullness JDK

(
    cd ${CHECKERFRAMEWORK}/checker/jdk/nullness/build

    for f in `find * -name '*\.class' -print` ; do
        CLASSPATH=${CP} extract-annotations "$f" 1>&2
        [ ${RET} -eq 0 ] && RET=$?
    done
    
    for f in `find * -name '*\.jaif' -print` ; do
        mkdir -p "${TMPDIR}/`dirname $f`" && sed 's/^class .*$/& @AnnotatedFor({"nullness"})/' < "$f" > "${TMPDIR}/$f"
        [ ${RET} -eq 0 ] && RET=$?
    done
)

[ ${RET} -ne 0 ] && echo "stage 1 failed" 1>&2 && rm -rf ${TMPDIR} && exit ${RET}


# Stage 2: convert stub files to JAIFs

(
    # main class of conversion utility
    CONV=org.checkerframework.framework.stub.ToIndexFileConverter

    cd "${CHECKERFRAMEWORK}"
    [ -z "`ls`" ] && echo "no files" 1>&2 && rm -rf ${TMPDIR} && exit 1

    for f in `find * -name '*\.astub' -print` ; do
        java -cp ${CP} ${CONV} $f
        x=$?
        if [ $x -eq 0 ] ; then
            d=`dirname $f`
            j="$d/`basename $f .astub`.jaif"
            # strip out annotation definitions and igj and javari annotations
            mkdir -p "${TMPDIR}/$d" && awk '
                BEGIN {x=1}
                /^annotation/ {x=-1}
                /^package/ {x=0;i=0;split("",a)}
                /^class/ {for(j=0;j<i;++j){print a[j]};split("",a);x=1;i=0}
                {if(x==0){a[i++]=$0}{if(x>0)print}}
            ' < "$j" | sed 's/ @[.[:alnum:]]*javari[^ ]*\b//g;s/ @[.[:alnum:]]*igj[^ ]*\b//g' > "${TMPDIR}/$j"
        else
            [ ${RET} -ne 0 ] || RET=$x
        fi
    done
)

[ ${RET} -ne 0 ] && echo "stage 2 failed" 1>&2 && rm -rf ${TMPDIR} && exit ${RET}


# Stage 3: combine JAIFs and write to stdout

(
    # write out annotation defs
    wget -O - https://types.cs.washington.edu/checker-framework/annotation-defs.jaif 1>&2
    RET=$?
    if [ ${RET} -eq 0 ] ; then
        # write out JAIFs in TMPDIR, filtering out annotation defs
        find ${TMPDIR}/* -name '*\.jaif' -print | xargs awk '
            BEGIN {x=1}                       # initial state: print on
            /^annotation/ {x=-1}              # omit until class or package
            /^package/ {x=0;i=0;split("",a)}  # print only if class follows
            /^class/ {for(j=0;j<i;++j){print a[j]};split("",a);x=1;i=0}
            {if(x==0){a[i++]=$0}{if(x>0)print}}
        '
    fi
) > ${TMPDIR}/JAIF
mv ${TMPDIR}/JAIF ${TMPDIR}/jdk.jaif  # avoid appending file to itself

[ ${RET} -ne 0 ] && echo "stage 3 failed" 1>&2 && rm -rf ${TMPDIR} && exit ${RET}


# Stage 4: annotate JDK

(
    cd ${JDK}/src/share/classes && find * -name '*\.java' -print | CLASSPATH=${CP} xargs insert-annotations-to-source ${TMPDIR}/jdk.jaif
    RET=$?
    [ ${RET} -eq 0 ] && cp ${TMPDIR}/jdk.jaif ${HOME}/sandbox
)

[ ${RET} -ne 0 ] && echo "stage 4 failed" 1>&2


#rm -rf ${TMPDIR}
exit ${RET}

