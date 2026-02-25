source("~/infinitetrading/src/api/getGasBalances.R")

addresses <- c(
  "0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5",
  "0x7462da033c5cceB21691D2447af34f3E333E0b85",
  "0xb2e2b1f036f31a9a97d3fc377a47581c813123aa",
  "0x6ca4166eefd64b5f607f12fb0c3fbae233897757"
)
n = length(addresses)
balances <- getGasBalances(addresses,"ethereum")
print("Gas balances on Ethereum:")
for (i in 1:n) {
        print(paste0("address: ", addresses[i]," ",balances[i], " ETH"))
}
balances <- getGasBalances(addresses,"base")
print("Gas balances on Base:")
for (i in 1:n) {
        print(paste0("address: ", addresses[i]," ",balances[i], " ETH"))
}

balances <- getGasBalances(addresses,"polygon")
print("Gas balances on Polygon")
for (i in 1:n) {
        print(paste0("address: ", addresses[i]," ",balances[i], " MATIC"))
}

balances <- getGasBalances(addresses,"arbitrum")
print("gas balances on Arbitrum:")
for (i in 1:n) {
        print(paste0("address: ", addresses[i]," ",balances[i], " ETH"))
}

balances <- getGasBalances(addresses,"optimism")
print("Gas balances on Optimism:")
for (i in 1:n) {
        print(paste0("address: ", addresses[i]," ",balances[i], " ETH"))
}
