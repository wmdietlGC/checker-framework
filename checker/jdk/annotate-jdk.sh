#!/bin/sh

# generates the annotated JDK from old annotation sources (nullness JDK
# and subfiles); to be run after building the full JDK (from source,
# without annotations) and the Checker Framework

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

[ ${RET} -ne 0 ] && echo "stage 2 failed" 1>&2 && exit ${RET}


# Stage 3: incorporate Stage 2 JAIFs into hierarchy built in Stage 1

rm -rf "${JAIFDIR}"

(
    # write out JAIFs in TMPDIR, replacing (bogus) annotation defs
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
    cd "${JDK}/src/share/classes" || exit $?
    for f in `find * -name '*\.java' -print` ; do
        BASE="${JAIFDIR}/`dirname $f`/`basename $f .java`"
        for g in ${BASE}.jaif ${BASE}\$*.jaif ; do
            if [ -r "$g" ] ; then
                CLASSPATH=${CP} insert-annotations-to-source "$g" "$f"
                [ ${RET} -ne 0 ] || RET=$?
            fi
        done
    done
)

[ ${RET} -ne 0 ] && echo "stage 4 failed" 1>&2
exit ${RET}


# Stage 5: compile
# (to be integrated)


# Stage 6: insert annotations into symbol file
# (to be integrated)

