#!/bin/bash

script=$1
network=$2
while true; do
  echo -e "\nRunning Rscript $script $network"
  sleep 2
  Rscript "$script" "$network"
done
~            
