#!/bin/bash -e
TEMP0=$(mktemp)
cat /dev/stdin > $TEMP0
echo "post-processing lint output"

> verilator.lint
while read -r line; do
	echo "$line"
    WARNING=`echo "$line" | awk '{print $1;}'`
    echo $WARNING
    if [[ $WARNING == "%Warning-WIDTH:" ]]; then

    	grep -P "%Warning-WIDTH:.+?expects (\d+) bits(?:[^C]|C(?!ONST))*(CONST)?.+(expects|generates) (\d+) bits"
    	if [ $SIZE_0 -gt $SIZE_1 ]; then
    		echo "$line" >> verilator.lint
    	else
    		echo "$line" >> verilator.lint
    	fi
    else
    	echo "$line" >> verilator.lint
    fi
done < $TEMP0

NO_OF_SRC_ERRORS=$((`wc -l < verilator.lint` - 1))
echo "Errors from non-generated sources: "$NO_OF_SRC_ERRORS
if [ "$NO_OF_SRC_ERRORS" -ne 0 ]; then
	cat verilator.lint
	false
fi

