
peaks_strategy = function(pair="BTCUSDT",maType="EMA",data_in=NULL,delay=2,backtest=TRUE,timeframe="1h",strategy=TRUE,return_signals=TRUE, training_size=5000,n=5,print=TRUE,exchange_fee=0.001,stop_loss=0.025,chart=FALSE) {
  require(TTR); require(httr); require(rgdax); require(data.table); require(snakecase); require(quantmod)
  data = pull_data(pair=pair,timeframe=timeframe,training_size=training_size,data_in=data_in)
  maType=toupper(maType); close = Cl(data); open = Op(data); hi = Hi(data); lo = Lo(data)
  if (maType == "EMA") { ema = EMA(close,n=n) }
  else if (maType == "SMA") { ema = SMA(close,n=n) }
  ndata= length(ema)
  first_price = open[n]
  last_price = close[ndata]
  hold_returns = (last_price - first_price)/first_price
  ema_adjusted = ema[n:ndata]
  peaks = find_peaks(ema_adjusted,m=13) + (n-1) + delay
  bottoms = find_peaks(-ema_adjusted,m=13) + (n-1) + delay
  if (chart) {
    chartSeries(ts(data),name="Peaks and bottoms")
    positions = bottoms; negative_positions = peaks
    plot(addPoints(x=positions,y=(lo[positions] - 0.01*lo[positions]),pch=17,col="green",on=1))
    plot(addPoints(x=negative_positions,y=(hi[negative_positions] + 0.01*hi[negative_positions]),pch=25,col="red",on=1))
    addEMA(n=n,on=1,col="purple")
  }
  trades = 0;
  profits = c();
  signals = rep(0,ndata)
  entry = FALSE
  model_signals = rep(0,ndata)
  for (i in 1:ndata) {
    cond = which(bottoms == i)
    if (length(cond) > 0) {
      if (cond > 0 & !entry) {
        entry=TRUE
        buy_price = open[bottoms[cond]]
        signals[i] = 1
        stop_price = buy_price - stop_loss*buy_price
      }
    }
    cond = which(peaks == i)
    if (length(cond) > 0) {
      if (cond > 0 & entry) {
        entry=FALSE
        trades = trades + 1
        sell_price = open[peaks[cond]]
        profit = max((sell_price - buy_price)/buy_price - exchange_fee*2,-stop_loss - exchange_fee*2)
        profits = c(profits,profit)
        if (print) { cat("Trade #",trades," buy price: ",buy_price, "sell price: ", sell_price, " profit: ", profit*100,"%\n" ) }
        signals[i] = -1
      }
    }
    if (entry) { model_signals[i] = 1 }
    else { model_signals[i] = -1 }
  }
  initial = 1000; bag = initial
  for (i in 1:length(profits)) { bag = bag + profits[i]*bag }
  bag_fixed = sum(initial*profits); alpha = (sum(profits) - hold_returns)
  if (strategy) { 
    strategy = c() 
    strategy$candles = data 
    strategy$pair = pair
    strategy$signals = signals
    if (backtest) { 
      bt = signals_backtester(strategy,chart=FALSE)
      reports_backtest(bt,model_name="Peaks and bottoms")
      }
  }
  if (print) {
    cat("Average profit: ",round(mean(profits)*100,2),"%\n"); cat("Median profit ",round(median(profits)*100,2),"%\n")
    cat("Sum of profits ",round(sum(profits)*100,2),"%\n"); cat("Alpha: ",round(alpha*100,2),"%\n")
    cat("Hold returns: ",round(hold_returns*100,2),"%\n")
    cat("Dolllar value of your portfolio if you reinvest everything using a bag of ",initial," total: ",bag,"\n")
    cat("Dolllar value of your portfolio if you use a fixed bag of ",initial," total: ",bag_fixed,"\n")
  }
  if (return_signals) { return(model_signals) }
  returns = c()
  returns$profit = sum(profits)
  returns$alpha = round((sum(profits) - hold_returns)*100,2)
  return(returns)
}

