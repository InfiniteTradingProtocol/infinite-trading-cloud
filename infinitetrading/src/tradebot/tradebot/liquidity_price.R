#################################
# File: liquidity_price.R
# Description:  a general function that extract data from the specified exchange
# Author:  R.Clare
#################################
#
#This function calculates the closer price with considerable amount of liquidity
#Where the most of the liquidity is
#Can be used for both asks/bids
#
#################################


liquidity_price = function(pair = "LTC-BTC",exchange="Coinbase",level = 3,chart=TRUE,upper_threshold=0.05,lower_threshold=0.05,peaks_smooth=3,limit=1000,data_in=NULL) {
  exchange = tolower(exchange); pair = toupper(pair); 
  info = get_depth(pair=pair,exchange=exchange,level=level,limit=limit,data_in=data_in)
  
  asks_prices = info$asks[,1]
  asks_sizes = info$asks[,2]
  bids_prices = info$bids[,1]
  bids_sizes = info$bids[,2]
  
  asks_prices = as.numeric(unlist(asks_prices))
  bids_prices = as.numeric(unlist(bids_prices))
  asks_sizes = as.numeric(unlist(asks_sizes))
  bids_sizes = as.numeric(unlist(bids_sizes))
  

  n_asks = length(asks_prices)
  n_bids = length(bids_prices)

  asks_cumulative = rep(0,n_asks);
  bids_cumulative = rep(0,n_bids);
  
  asks_cumulative[1] = asks_sizes[1]
  bids_cumulative[1] = bids_sizes[1]
  signal = FALSE; buy_stop = 0; sell_stop = 0;

  #price limits to watch
  best_price = min(asks_prices)
  
  price_threshold = best_price + upper_threshold*best_price
  
  for (i in 2:n_asks) {
    if ( ( (asks_prices[i] < price_threshold) && (!isTRUE(signal)) )) { 
      asks_cumulative[i] = asks_cumulative[i-1] + asks_sizes[i]
    } 
    else if (!isTRUE(signal)) { buy_stop = i; signal = TRUE; }
  }
  
  signal = FALSE;
  
  best_price = max(bids_prices)
  price_threshold = best_price - lower_threshold*best_price
  
  for (i in 2:n_bids) {
    if ( (bids_prices[i] > price_threshold) && (!isTRUE(signal)) )  { 
      bids_cumulative[i] = bids_cumulative[i-1] + bids_sizes[i]
    }
    else if (!isTRUE(signal)) { sell_stop = i; signal = TRUE; }
    bids_cumulative[i] = bids_cumulative[i-1] + bids_sizes[i]
  }
  
  bids_peaks_indexes = find_peaks(bids_sizes[1:(sell_stop -1)],m=peaks_smooth)
  asks_peaks_indexes = find_peaks(asks_sizes[1:(buy_stop -1)],m=peaks_smooth)
  
  asks_real_indexes = c(); bids_real_indexes = c();
  
  mean_bids_size = mean(bids_sizes[bids_peaks_indexes])
  mean_asks_size = mean(asks_sizes[asks_peaks_indexes])
  
  for (index in bids_peaks_indexes) {
    if (bids_sizes[index] > mean_bids_size) { bids_real_indexes = c(bids_real_indexes,index) } 
  }
  for (index in asks_peaks_indexes) {
    if (asks_sizes[index] > mean_asks_size) { asks_real_indexes = c(asks_real_indexes,index) } 
  }
  if (isTRUE(chart)) {
    
    #bids plots
    par(mfrow=c(2,2))
    plot(bids_prices[1:(sell_stop - 1)],bids_sizes[1:(sell_stop-1)],type="l",main=paste(pair,"Bids",sep=" "),col="green",xlab="Bids",ylab="Size")
    points(x=bids_prices[bids_real_indexes],y=bids_sizes[bids_real_indexes],type="p",col="black")
    abline(h=mean_bids_size,col="green")  
    
    #asks plot
    plot(asks_prices[1:(buy_stop - 1)],asks_sizes[1:(buy_stop-1)],type="l",col="red",xlab="Asks",ylab="Size",main=paste(pair,"asks",sep=" "))
    points(x=asks_prices[asks_real_indexes],y=asks_sizes[asks_real_indexes],type="p",col="black")
    abline(h=mean_asks_size,col="green")  
    
    #cumulative asks and bids plot    
    plot(bids_prices[1:(sell_stop - 1)],bids_cumulative[1:(sell_stop-1)],type="l",col="green",xlab="Bids",ylab="Cumulative")
    plot(asks_prices[1:(buy_stop - 1)],asks_cumulative[1:(buy_stop-1)],type="l",col="red",xlab="Asks",ylab="Cumulative")
    par(mfrow=c(1,1))
  }
  else {
    liquidity = c()
    liquidity$bid = first(bids_prices[bids_real_indexes],1)
    liquidity$ask = first(asks_prices[asks_real_indexes],1)
    return(liquidity)
  }
}
