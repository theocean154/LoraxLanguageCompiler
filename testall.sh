#!/bin/sh

#
# Authors:
# Chris D'Angelo
# Zhaarn Maheswaran
# Special thanks Stephen Edward's MicroC which provided background knowledge.
#

lorax="./lorax"
binaryoutput="./a.out"

# Set time limit for all operations
ulimit -t 30

globallog=testall.log
rm -f $globallog
error=0
globalerror=0

keep=0

Usage() {
    echo "Usage: testall.sh [options] [.lrx files]"
    echo "-k    Keep intermediate files"
    echo "-h    Print this help"
    exit 1
}

SignalError() {
    if [ $error -eq 0 ] ; then
	echo "FAILED"
	error=1
    fi
    echo "  $1"
}

# Compare <outfile> <reffile> <difffile>
# Compares the outfile with reffile.  Differences, if any, written to difffile
Compare() {
    generatedfiles="$generatedfiles $3"
    echo diff -b $1 $2 ">" $3 1>&2
    diff -b "$1" "$2" > "$3" 2>&1 || {
	SignalError "$1 differs"
	echo "FAILED $1 differs from $2" 1>&2
    }
}

# Run <args>
# Report the command, run it, and report any errors
Run() {
    echo $* 1>&2
    eval $* || { 
        if [[ $5 != *fail* ]]; then
	       SignalError "$1 failed on $*"
	       return 1
        fi
    }
}

CheckParser() {
    error=0
    basename=`echo $1 | sed 's/.*\\///
                             s/.lrx//'`
    reffile=`echo $1 | sed 's/.lrx$//'`
    basedir="`echo $1 | sed 's/\/[^\/]*$//'`/."

    echo -n "$basename..."

    echo 1>&2
    echo "###### Testing $basename" 1>&2

    generatedfiles=""

    generatedfiles="$generatedfiles ${basename}.a.out" &&
    Run "$lorax" "-a" $1 ">" ${basename}.a.out &&
    Compare ${basename}.a.out ${reffile}.out ${basename}.a.diff

    if [ $error -eq 0 ] ; then
    if [ $keep -eq 0 ] ; then
        rm -f $generatedfiles
    fi
    echo "OK"
    echo "###### SUCCESS" 1>&2
    else
    echo "###### FAILED" 1>&2
    globalerror=$error
    fi 
}

CheckSemanticAnalysis() {
    error=0
    basename=`echo $1 | sed 's/.*\\///
                             s/.lrx//'`
    reffile=`echo $1 | sed 's/.lrx$//'`
    basedir="`echo $1 | sed 's/\/[^\/]*$//'`/."

    echo -n "$basename..."

    echo 1>&2
    echo "###### Testing $basename" 1>&2

    generatedfiles=""

    generatedfiles="$generatedfiles ${basename}.s.out" &&
    Run "$lorax" "-s" $1 ">" ${basename}.s.out &&
    Compare ${basename}.s.out ${reffile}.out ${basename}.s.diff

    if [ $error -eq 0 ] ; then
    if [ $keep -eq 0 ] ; then
        rm -f $generatedfiles
    fi
    echo "OK"
    echo "###### SUCCESS" 1>&2
    else
    echo "###### FAILED" 1>&2
    globalerror=$error
    fi 
}

Check() {
    error=0
    basename=`echo $1 | sed 's/.*\\///
                             s/.lrx//'`
    reffile=`echo $1 | sed 's/.lrx$//'`
    basedir="`echo $1 | sed 's/\/[^\/]*$//'`/."

    echo -n "$basename..."

    echo 1>&2
    echo "###### Testing $basename" 1>&2

    generatedfiles=""

    # old from microc - interpreter
    # generatedfiles="$generatedfiles ${basename}.i.out" &&
    # Run "$lorax" "-i" "<" $1 ">" ${basename}.i.out &&
    # Compare ${basename}.i.out ${reffile}.out ${basename}.i.diff

    generatedfiles="$generatedfiles ${basename}.c.out" &&
    Run "$lorax" "-c" $1 ">" ${basename}.c.out &&
    Compare ${basename}.c.out ${reffile}.out ${basename}.c.diff

    # Report the status and clean up the generated files

    if [ $error -eq 0 ] ; then
    if [ $keep -eq 0 ] ; then
        rm -f $generatedfiles
    fi
    echo "OK"
    echo "###### SUCCESS" 1>&2
    else
    echo "###### FAILED" 1>&2
    globalerror=$error
    fi
}
CheckFail() {
    error=0
    basename=`echo $1 | sed 's/.*\\///
                             s/.lrx//'`
    reffile=`echo $1 | sed 's/.lrx$//'`
    basedir="`echo $1 | sed 's/\/[^\/]*$//'`/."

    echo -n "$basename..."

    echo 1>&2
    echo "###### Testing $basename" 1>&2

    generatedfiles=""

    # old from microc - interpreter
    # generatedfiles="$generatedfiles ${basename}.i.out" &&
    # Run "$lorax" "-i" "<" $1 ">" ${basename}.i.out &&
    # Compare ${basename}.i.out ${reffile}.out ${basename}.i.diff

    generatedfiles="$generatedfiles ${basename}.c.out" &&
    { 
        Run "$lorax" "-b" $1 "2>" ${basename}.c.out || 
        Run "$binaryoutput" ">" ${basename}.b.out 
    } &&
    Compare ${basename}.c.out ${reffile}.out ${basename}.c.diff

    # Report the status and clean up the generated files

    if [ $error -eq 0 ] ; then
    if [ $keep -eq 0 ] ; then
        rm -f $generatedfiles
    fi
    echo "OK"
    echo "###### SUCCESS" 1>&2
    else
    echo "###### FAILED" 1>&2
    globalerror=$error
    fi
}

TestRunningProgram() {
    error=0
    basename=`echo $1 | sed 's/.*\\///
                             s/.lrx//'`
    reffile=`echo $1 | sed 's/.lrx$//'`
    basedir="`echo $1 | sed 's/\/[^\/]*$//'`/."

    echo -n "$basename..."

    echo 1>&2
    echo "###### Testing $basename" 1>&2

    generatedfiles=""
    tmpfiles=""

    # old from microc - interpreter
    # generatedfiles="$generatedfiles ${basename}.i.out" &&
    # Run "$lorax" "-i" "<" $1 ">" ${basename}.i.out &&
    # Compare ${basename}.i.out ${reffile}.out ${basename}.i.diff

    generatedfiles="$generatedfiles ${basename}.f.out" &&
    tmpfiles="$tmpfiles tests/${basename}.lrx_lrxtmp.c a.out" &&
    Run "$lorax" "-b" $1 &&
    Run "$binaryoutput" ">" ${basename}.f.out &&
    Compare ${basename}.f.out ${reffile}.out ${basename}.f.diff
    
    rm -f $tmpfiles

    # Report the status and clean up the generated files

    if [ $error -eq 0 ] ; then
	if [ $keep -eq 0 ] ; then
	    rm -f $generatedfiles
	fi
	echo "OK"
	echo "###### SUCCESS" 1>&2
    else
	echo "###### FAILED" 1>&2
	globalerror=$error
    fi
}

while getopts kdpsh c; do
    case $c in
	k) # Keep intermediate files
	    keep=1
	    ;;
	h) # Help
	    Usage
	    ;;
    esac
done

shift `expr $OPTIND - 1`

if [ $# -ge 1 ]
then
    files=$@
else
    files="tests/test-*.lrx"
fi

for file in $files
do
    case $file in
    *test-parser*)
        CheckParser $file 2>> $globallog
        ;;
    *test-sa*)
        CheckSemanticAnalysis $file 2>> $globallog
        ;;
    *test-full*)
        TestRunningProgram $file 2>> $globallog
        ;;
    *test-fail*)
        CheckFail $file 2>> $globallog
        ;;
	*test-*)
	    Check $file 2>> $globallog
	    ;;
	*)
	    echo "unknown file type $file"
	    globalerror=1
	    ;;
    esac
done

exit $globalerror
