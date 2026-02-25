#!/bin/bash
sed -i 's/chain <- "MATIC_MAINNET"/chain <- "polygon-mainnet"/g' pool_comp_extract.R
sed -i 's/chain <- "OPT_MAINNET"/chain <- "opt-mainnet"/g' pool_comp_extract.R
sed -i 's/chain <- "BASE_MAINNET"/chain <- "base-mainnet"/g' pool_comp_extract.R
sed -i 's/chain <- "ARB_MAINNET"/chain <- "arb-mainnet"/g' pool_comp_extract.R
sed -i 's/chain <- "ETH_MAINNET"/chain <- "eth-mainnet"/g' pool_comp_extract.R
