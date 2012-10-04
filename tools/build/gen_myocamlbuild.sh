#!/usr/bin/env bash

set -u
set -e

# This script reads files config.{sh,ml}, build_rules*.ml, build_libs, build_tools
# in tools/build/ and uses them
# to build an ocamlbuild plugin in <build_dir>/myocamlbuild
#
# You can then run your compilations with:
# $ <build_dir>/myocamlbuild -no-plugin -j 6 <targets>


TOOLS_PATH=$OPALANG_REPO/tools
CONFIG_PATH=$TOOLS_PATH/build

CONFIG_SH=$CONFIG_PATH/config.sh
if [ ! -e $CONFIG_SH ]; then
    if [ -e $CONFIG_PATH/config.sh ]; then
        CONFIG_SH=$CONFIG_PATH/config.sh
    else
        echo "Error: config.sh not found. Please run ./configure"
        exit 1
    fi
fi

. $CONFIG_SH

. $TOOLS_PATH/platform_helper.sh

: ${BLDDIR:="$PWD"/tools/build}

CONFIG_ML=$CONFIG_PATH/config.ml
if [ ! -e $CONFIG_ML ]; then
    echo $BLDDIR/config.ml >&2
    if [ -e $BLDDIR/config.ml ]; then
        CONFIG_ML=$BLDDIR/config.ml
    else
        echo "Error: config.ml not found. Please run ./configure"
        exit 1
    fi
fi
if [ $CONFIG_ML -ot ${CONFIG_ML}i ]; then
    echo "[1m[31mWarning[0m: ${CONFIG_ML}i is newer than $CONFIG_ML, you should probably re-run ./configure" >&2
fi


BUILD_DIR="_build"
BUILD_RULES="tools/build/build_rules.ml"
BUILD_LIBS="tools/build/build_libs"
BUILD_TOOLS="tools/build/build_tools"

while [ $# -gt 0 ]; do
    case $1 in
        -private)
            BUILD_RULES="tools/build/build_rules*.ml"
            BUILD_LIBS="tools/build/build_libs*"
            BUILD_TOOLS="tools/build/build_tools*"
            ;;
        -build-dir)
            if [ $# -lt 2 ]; then echo "Error: option $1 requires an argument"; exit 1; fi
            shift
            BUILD_DIR="$1"
            ;;
        -bytecode)
            BYTECODE=1
            ;;
        *)
            echo "Error: unknown option $1"
            exit 1
    esac
    shift
done

MYOCAMLBUILD=$BUILD_DIR/myocamlbuild.ml

mkdir -p $BUILD_DIR
mkdir -p $BUILD_DIR/$CONFIG_PATH

# Generate the myocamlbuild.ml
{
    SED_FILTER='s/#.*$//'
    if [ "${BYTECODE:-}" ]; then
        SED_FILTER=$SED_FILTER'; s/\.native\>/.byte/g'
    fi
    if [ "$IS_WINDOWS" ]; then
        SED_FILTER=$SED_FILTER'; s/\.o\>/\.obj/g'
    fi
    echo "(* ****************************************************************************** *)"
    echo "(*                    File generated by bld: DO NOT EDIT.                         *)"
    echo "(*         See build_libs*, build_tools* and build_rules*.ml instead.             *)"
    echo "(* ****************************************************************************** *)"
    echo
    echo "#1 \"$CONFIG_ML\""
    cat $CONFIG_ML
    echo "#1 \"$BLDDIR/myocamlbuild_prefix.ml\""
    cat $BLDDIR/myocamlbuild_prefix.ml
    for i in $BUILD_TOOLS; do
        if [ -e "$i" ]; then
            echo "#1 \"$i\""
            sed "$SED_FILTER" $i |
            awk '/^external/ { print "set_tool ~internal:false \""$2"\" \""$3"\";" }
                 /^internal/ { print "set_tool ~internal:true \""$2"\" \""$3"\";" }'
        fi
    done
    for i in $BUILD_LIBS; do
        if [ -e "$i" ]; then
            echo "#1 \"$i\""
            awk 'BEGIN { split (ENVIRON["DISABLED_LIBS"],a); for (i in a) disabled[a[i]] = 1 }
                 /^external/ { print "mlstate_lib ~dir:\"lib/opa/static\" \""$2"\";" }
                 /^internal/ && ! ($2 in disabled) \
                   { print "internal_lib", $3 ? "~dir:\""$3"\"" : "", "\""$2"\";" }' $i
        fi
    done
    for i in $BUILD_RULES; do
        if [ -e "$i" ]; then
            echo "#1 \"$i\""
            cat $i
            echo ";"
        fi
    done
    echo "#1 \"$BLDDIR/myocamlbuild_suffix.ml\""
    cat $BLDDIR/myocamlbuild_suffix.ml
} > $MYOCAMLBUILD

# Compile the myocamlbuild

OCAMLBUILD_LIB=$($OCAMLBUILD -where)

cp $CONFIG_ML ${CONFIG_ML}i $BUILD_DIR/$CONFIG_PATH/
cd $BUILD_DIR
if [ "${BYTECODE:-}" ]; then
    OCAMLC=${OCAMLOPT/ocamlopt/ocamlc}
    $OCAMLC -I $CONFIG_PATH -c $CONFIG_PATH/config.mli
    $OCAMLC -I $CONFIG_PATH -c $CONFIG_PATH/config.ml
    $OCAMLC -w y -I "$OCAMLBUILD_LIB" -I $CONFIG_PATH unix.cma ocamlbuildlib.cma $CONFIG_PATH/config.ml myocamlbuild.ml "$OCAMLBUILD_LIB"/ocamlbuild.cmo -o myocamlbuild
else
    $OCAMLOPT -I $CONFIG_PATH -c $CONFIG_PATH/config.mli
    $OCAMLOPT -I $CONFIG_PATH -c $CONFIG_PATH/config.ml
    $OCAMLOPT -w y -I "$OCAMLBUILD_LIB" -I $CONFIG_PATH unix.cmxa ocamlbuildlib.cmxa $CONFIG_PATH/config.cmx myocamlbuild.ml "$OCAMLBUILD_LIB"/ocamlbuild.cmx -o myocamlbuild
fi
