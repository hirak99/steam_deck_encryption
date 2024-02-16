#!/bin/bash

# Note: If any change is made here, please change README.md.

# This is solely to test the logic of removing tpm from a comma delimited module_blacklist.
# There are 4 cases -
# Case 1: ...=tpm
# Case 2: ...=A,tpm
# Case 3: ...=tpm,B
# Case 4: ...=A,tpm,B
# Also note that sed does not support specifying non greedy matches.

set -ueo pipefail

# Not the real grubfile, but one where test cases will be set.
readonly GRUBFILE=$(mktemp /tmp/tpm_removal_testXXXXXXX)

trap "rm $GRUBFILE" EXIT

readonly TPM_BLACKLIST_REGEX='^\s*GRUB_CMDLINE_LINUX_DEFAULT\b.*\bmodule_blacklist=[^\s]*,?tpm,?\s*\b'

for fname in $(ls | grep '^case'); do
    echo Testing $fname ...
    cp $fname $GRUBFILE
    # For the line with tpm blacklist, comment out the original line, and
    # remove the tpm blacklist.
    if grep -E -q "${TPM_BLACKLIST_REGEX}" $GRUBFILE; then
        sed -E -i "/${TPM_BLACKLIST_REGEX}/"\
'{h;s/^/# Modified from: /p;x;'\
's/(module_blacklist=)([^\s]*)?\b(tpm,?)\b/\1\2/;s/,([ \s$])/\1/;}' $GRUBFILE
    fi

    # cp $GRUBFILE expected_$fname
    if ! diff expected_$fname $GRUBFILE; then
        echo "Unexpected diff."
        exit -1
    fi
done

echo All good.
