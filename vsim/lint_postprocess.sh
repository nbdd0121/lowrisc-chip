#!/bin/bash
set -e
TEMP=$(mktemp)
cat /dev/stdin > $TEMP
echo "post-processing lint output"
NO_OF_GEN_SRC_ERRORS=`grep generated-src $TEMP | wc -l`
echo "Errors from generated sources:     "$NO_OF_GEN_SRC_ERRORS
# grep -v generated-src $TEMP | grep -v %Warning-WIDTH > verilator.lint
grep -v generated-src $TEMP > verilator.lint
NO_OF_SRC_ERRORS=$((`wc -l < verilator.lint` - 2))
echo "Errors from non-generated sources: "$NO_OF_SRC_ERRORS
if [ "$NO_OF_SRC_ERRORS" -eq 0 ]; then
	cat verilator.lint
	false
else
	true
fi