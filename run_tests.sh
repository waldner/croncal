#!/bin/bash

ss=$(command -v shellspec)

if [ "$ss" = "" ]; then
  echo "shellspec not found" >&2
  exit 1
fi

TZ=Europe/London "$ss"
