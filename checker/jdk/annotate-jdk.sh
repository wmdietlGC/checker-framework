#!/bin/sh

# Generates the annotated JDK from old annotation sources (nullness JDK
# and stubfiles).  The goal is to transfer all the annotations from the
# sources to the JDK source, which will be the new home for all the
# annotations associated with the checkers that are distributed with the
# Checker Framework.
#
# Prerequisites:
#
# 1.  Clone and build the checker framework from source.
#     git clone https://github.com/typetools/checker-framework
#     cd checker-framework && ant
#     
# 2.  Clone the OpenJDK 8u repository and sub-repositories.
#     hg clone http://hg.openjdk.java.net
#     cd jdk8u && sh ./get_source
#
# 3.  Build OpenJDK, following the instructions in README-builds.html.
#     (Dan isn't sure this is necessary.)
#
# 4.  Set JAVA_HOME to build/(name of output directory).
#
# This script should be run from the top-level OpenJDK directory.
#
# 
# Build stages:
#
# 0.  Restore comments from old nullness JDK and stubfiles.
#     (These comments explain non-intuitive annotation choices, etc.
#     This stage should run only once.)
#
# 1.  Extract annotations from the nullness JDK into JAIFs.
#
# 2.  Convert old stubfiles into JAIFs.
#
# 3.  Combine the results of the previous two stages.
#
# 4.  Insert annotations from JAIFs into JDK source files.
#
# 5.  Compile the annotated JDK.
#
# 6.  Combine the results of the previous two stages.

WD="`pwd`"            # run from top directory of jdk8u clone
JDK="${WD}/jdk"       # JDK to be annotated
TMPDIR="${WD}/tmp"    # directory for temporary files
JAIFDIR="${WD}/jaifs" # directory for generated JAIFs

# parameters derived from environment
JSR308=`[ -d "${CHECKERFRAMEWORK}" ] && cd "${CHECKERFRAMEWORK}/.." && pwd`
AFU="${JSR308}/annotation-tools"
AFUJAR="${AFU}/annotation-file-utilities/annotation-file-utilities.jar"
CFJAR="${CHECKERFRAMEWORK}/checker/dist/checker.jar"
LTJAR="${JSR308}/jsr308-langtools/dist/lib/javac.jar"
JDJAR="${JSR308}/jsr308-langtools/dist/lib/javadoc.jar"
CP=".:${JDK}/build/classes:${LTJAR}:${JDJAR}:${CFJAR}:${AFUJAR}:${CLASSPATH}"

# return value
RET=0

# make vars visible to awk
export WD
export TMPDIR


# Stage 0: restore old comments

# download patch
[ -r annotated-jdk-comment-patch.jaif ] || wget https://types.cs.washington.edu/checker-framework/annotated-jdk-comment-patch.jaif || exit $?
(cd "${JDK}" && patch -p1 < annotated-jdk-comment-patch.jaif)


# Stage 1: extract JAIFs from nullness JDK

rm -rf "${TMPDIR}"
mkdir "${TMPDIR}"

(
    cd "${CHECKERFRAMEWORK}/checker/jdk/nullness/build"
    [ -z "`ls`" ] && echo "no files" 1>&2 && exit 1

    for f in `find * -name '*\.class' -print` ; do
        CLASSPATH="${CP}" extract-annotations "$f" 1>&2
        [ ${RET} -eq 0 ] && RET=$?
    done

    for f in `find * -name '*\.jaif' -print` ; do
        mkdir -p "${TMPDIR}/`dirname $f`" && sed 's/^class .*$/& @AnnotatedFor({"nullness"})/' < "$f" > "${TMPDIR}/$f"
        [ ${RET} -eq 0 ] && RET=$?
    done
)

[ ${RET} -ne 0 ] && echo "stage 1 failed" 1>&2 && exit ${RET}


# Stage 2: convert stub files to JAIFs

# download annotation definitions
[ -r annotation-defs.jaif ]\
 || wget https://types.cs.washington.edu/checker-framework/annotation-defs.jaif\
 || exit $?

(
    cd "${CHECKERFRAMEWORK}"
    [ -z "`ls`" ] && echo "no files" 1>&2 && exit 1

    for f in `find * -name '*\.astub' -print` ; do
        java -cp "${CP}" org.checkerframework.framework.stub.ToIndexFileConverter "$f"
        x=$?
        [ ${RET} -ne 0 ] || RET=$x
        g="`dirname $f`/`basename $f .astub`.jaif"
        [ -r "$g" ] && cat "$g" && rm -f "$g"
    done
) | awk '
    # save class sections from converted JAIFs to hierarchical JAIF directory
    BEGIN {out="";adefs=ENVIRON["WD"]"/annotation-defs.jaif"}
    /^package / {
        l=$0;i=index($2,":");d=(i?substr($2,1,i-1):$2)
        if(d){gsub(/\./,"/",d)}else{d=""}
        d=ENVIRON["TMPDIR"]"/"d
    }
    /^class / {
        i=index($2,":");c=(i?substr($2,1,i-1):$2)
        if(c) {
            o=d"/"c".jaif"
            if (o!=out) {
                if(out){close(out)};out=o
                if(system("test -s "out)!=0) {
                    system("mkdir -p "d" && cp "adefs" "out)
                    printf("%s\n",l)>>out  # current pkg decl
                }
            }
        }
    }
    {if(out){print>>out}}
    END {close(out)}
'
# TODO: insert @AnnotatedFor annotations

[ ${RET} -ne 0 ] && echo "stage 2 failed" 1>&2 && exit ${RET}


# Stage 3: incorporate Stage 2 JAIFs into hierarchy built in Stage 1

(
    rm -rf "${JAIFDIR}"
    # write out JAIFs from TMPDIR, replacing (bogus) annotation defs
    for f in `(cd "${TMPDIR}" && find * -name '*\.jaif' -print)` ; do
        # first write out standard annotation defs
        g="${JAIFDIR}/$f"
        mkdir -p `dirname $g` && cp annotation-defs.jaif "$g"

        # then strip out empty annotation defs
        awk '
            BEGIN {x=1}                       # initial state: print on
            /^annotation/ {x=-1}              # omit until class or package
            /^package/ {x=0;i=0;split("",a)}  # print only if class follows
            /^class/ {for(j=0;j<i;++j){print a[j]};split("",a);x=1;i=0}
            {if(x==0){a[i++]=$0}{if(x>0)print}}
        ' < "${TMPDIR}/$f" >> "$g"
    done
)

[ ${RET} -ne 0 ] && echo "stage 3 failed" 1>&2 && exit ${RET}


# Stage 4: insert annotations from JAIFs into JDK source

(
    # first ensure source is unchanged from repo
    cd "${JDK}/src/share/classes" || exit $?
    hg revert -C com java javax jdk org sun
    rm -rf annotated

    for f in `find * -name '*\.java' -print` ; do
        BASE="${JAIFDIR}/`dirname $f`/`basename $f .java`"
        # must insert annotations on inner classes as well
        for g in ${BASE}.jaif ${BASE}\$*.jaif ; do
            if [ -r "$g" ] ; then
                CLASSPATH=${CP} insert-annotations-to-source "$g" "$f"
                [ ${RET} -ne 0 ] || RET=$?
            fi
        done
    done

    # copy annotated source files over originals
    rsync -au annotated/* .
)

[ ${RET} -ne 0 ] && echo "stage 4 failed" 1>&2 && exit ${RET}


# Stage 5: compile
# (to be integrated)

#TODO


# Stage 6: insert annotations into symbol file
# (to be integrated)

#TODO

