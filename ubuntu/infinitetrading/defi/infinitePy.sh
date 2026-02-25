#!/bin/bash

script=$1
while true; do
  echo -e "\nRunning Rscript $script"
  sleep 2
  python3 "$script"
done
