#!/bin/bash

Describe "test $tst"
  Parameters:dynamic
  for tst in tests/*; do

    start=$(sed -n 1p "$tst")
    end=$(sed -n 2p "$tst")
    crontab=$(awk '
        /^---$/ { count++; next }
        count == 1
    ' "$tst")
    out=$(awk '
        /^---$/ { count++; next }
        count == 2
    ' "$tst")

    %data "$start" "$end" "$crontab" "$out"
  done
  End

  It "runs test "
    When run ./croncal.pl -f <(echo "$3") -s "$1" -e "$2"
    The output should equal "$4"
  End
End
