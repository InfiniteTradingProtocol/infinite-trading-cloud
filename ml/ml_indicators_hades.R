# Model Indicator Matrix Function
# Authors: Richard Clare, Joshua Bonet, Joseph Bonet
# Tradery Labs 2021
#'@aliases Model Indicator Matrix Function
#'@note Function of all technical indicators found in TTR quantmod
#'@author Richard Clare, Joshua Bonet, Joseph Bonet
#'@seealso Model Indicator Matrix Function TTR quantmod
#'@keywords model indicator matrix function
#'@examples
#' test_candles = get_prices_coinbase("btc-usd",24*52*1,"1h")
#' test = ml_indicator_matrix(test_candles, price_type = "close", indicators = c("rsi","trix"), indicators_periods = c(14,12,4), oscillator_periods = c(20,20,20), ind_rep = c(1,2) )
#'@rdname ml_indicator_matrix()

######################################################################################################################################################################

require(TTR); require(quantmod);

#################################################### Get Prices Function #############################################################################################
get_price_type = function(candles, price_type = "close") { 
  price_type = tolower(price_type)
  if (is.OHLC(candles)) { 
    close = Cl(candles)
    high = Hi(candles)
    low = Lo(candles)
    open = Op(candles)
  }
  else { return(candles) }
  n = length(close)
  if (!any(price_type == c("close", "c", "open", "o", "ohlc4", "hl2", "high", "h", "l", "low", "med", "hlc3"))){ price_type = "prices" }
  if (price_type == "close" || price_type == "c") { return(close) }
  else if (price_type == "high" || price_type == "h") { return(high) }
  else if (price_type == "o" || price_type == "open") { return(open) }
  else if (price_type == "l" || price_type == "low") { return(low) }
  else if (price_type == "median") { }
  else if (price_type == "hlc3") { return((high+low+close)/3)}
  else if (price_type == "ohlc4") { return((high+low+close+open)/4)}
  else if (price_type == "hl2") { return((high+low)/2)}
  else if (price_type == "med") {
    median_prices = rep(0,n)
    for (i in 1:n) { 
      median_prices[i] = median(c(open[i], prices[i], high[i], low[i]))
    }
    return(median_prices)
  }
}

#################################################### Zero to One Function ############################################################################################
zero_to_one = function(vector){
  new_vector =c()
  vector[is.na(vector)]<-0
  max_vector = max(vector)
  min_vector = min(vector)
  for(k in 1:length(vector)){
    new_vector[k] = (max_vector-vector[k])/(max_vector-min_vector) 
  }
  return(new_vector)
}

################################################# Choppiness Indicator Function #######################################################################################
choppy_indicator_1 = function(candles, period_choppy) {
  hlc = cbind(Hi(candles),Lo(candles),Cl(candles))
  ALL_atr <- ATR(hlc, n = period_choppy) 
  ALL_atr <- ALL_atr[, c("trueHigh", "trueLow", "tr", "atr") ]
  tr <- ALL_atr[, c("tr")]
  trueHigh <- ALL_atr[, c("trueHigh")]
  trueLow <- ALL_atr[, c("trueLow")]
  n = length(tr)
  sum_tr = rep(0,n); max_trueHigh = rep(0,n); min_trueLow = rep(0,n)
  for (i in period_choppy:n) { 
    sum_tr[i] = sum(tr[i:(i-period_choppy + 1)])
    max_trueHigh[i] = max(trueHigh[(i-period_choppy + 1):i])
    min_trueLow[i] = min(trueLow[(i-period_choppy + 1):i])
  }
  true_range <- max_trueHigh - min_trueLow
  ## Choppiness Index 
  choppy <- 100 * (log10(sum_tr / true_range)) / (log10(period_choppy) )
  return(choppy)
}

#################################################### Oscillator Function #############################################################################################
oscillator = function(candles, periods = 7) { 
  n = length(candles)
  new_candles = rep(NA, n)
  NonNAindex <- which(!is.na(candles))
  firstNonNA <- min(NonNAindex)
  first_index = max(periods, firstNonNA)
  for (i in first_index:n) { 
    index = i - periods + 1
    maxcandles = max(candles[index:i])
    mincandles = min(candles[index:i])
    new_candles[i] = (candles[i]-mincandles)/(maxcandles-mincandles)
    if (is.na(new_candles[i])){
      new_candles[i] = 0
    }
  }
  new_candles
}

########################################### Model Indicator Matrix Function ###########################################################################################
ml_indicator_matrix = function(candles, price_type = "close", indicators = c("rsi","trix"), indicators_periods = c(14,12,4), ind_rep = c(1,2) ){ 
  if (is.OHLC(candles)) { 
    prices = get_price_type(candles, price_type = price_type)
    hl = cbind(Hi(candles),Lo(candles))
    hlc = cbind(Hi(candles),Lo(candles),Cl(candles))
    vo = Vo(candles)
  }
  else { prices = candles } 
  indicators = tolower(indicators)
  n = length(prices)
  n_indicators = length(indicators)
  if (is.null(ind_rep)) { ind_rep = rep(1,n_indicators) }
  index = 0;
  indicator = c()
  for (i in 1:n_indicators) { 
    index = index + ind_rep[i]
    
    ########################################### TTR #################################################################################################
    if(indicators[i] == "adx" || indicators[i] == "welles_wilders_directional_movement_index" || indicators[i] == "welles_adx" ){
      indicator = cbind(indicator,ADX(hlc, n = indicators_periods[index])) 
    }
    else if(indicators[i] == "adx_oscillator" ){
      adx = ADX(hlc, n = indicators_periods[index])
      osc = c()
      for (k in 1:ncol(adx)) {
        osc =cbind(osc,oscillator(adx[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc)
    }
    else if (indicators[i] == "aroon"){ 
      indicator = cbind(indicator,aroon(hl, n = indicators_periods[index]))
    }
    else if (indicators[i] == "aroon_oscillator"){ 
      aroon = aroon(hl, n = indicators_periods[index])
      osc = c()
      for (k in 1:ncol(aroon)) {
        osc =cbind(osc,oscillator(aroon[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    ## Average_True_Range.R
    else if(indicators[i] == "average_true_range" || indicators[i] == "atr"){
      indicator = cbind(indicator,ATR(hlc, n = indicators_periods[index]))
    }
    else if (indicators[i] == "atr_oscillator"){ 
      atr = ATR(hlc, n = indicators_periods[index])
      osc = c()
      for (k in 1:ncol(atr)) {
        osc =cbind(osc,oscillator(atr[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    else if(indicators[i] == "bb" || indicators[i] == "bbands" || indicators[i] == "bollinger" ||indicators[i] == "bollinger_bands"){
      indicator = cbind(indicator,BBands(hlc, n = indicators_periods[index]))
    }
    else if (indicators[i] == "bb_oscillator"){ 
      bb= BBands(hlc, n = indicators_periods[index])
      osc = c()
      for (k in 1:ncol(bb)) {
        osc =cbind(osc,oscillator(bb[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    
    
    else if(indicators[i] == "cci" || indicators[i] == "commodity_channel_index"){
      indicator= cbind(indicator,CCI(hlc, n = indicators_periods[index]))
    }
    else if(indicators[i] == "cci_oscillator" || indicators[i] == "commodity_channel_index_oscillator"){
      osc = oscillator(CCI(hlc, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "cci_sma_oscillator" || indicators[i] == "commodity_channel_index_sma_oscillator"){
      osc = oscillator(SMA(CCI(hlc, n = indicators_periods[index]), n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "cci_ema_oscillator" || indicators[i] == "commodity_channel_index_ema_oscillator"){
      osc = oscillator(EMA(CCI(hlc, n = indicators_periods[index]), n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "chaikin_ad"|| indicators[i] == "chaikin_accumulation_distribution" ){
      indicator = cbind(indicator,chaikinAD(hlc, vo))
    }
    else if(indicators[i] == "chaikin_ad_oscillator"|| indicators[i] == "chaikin_accumulation_distribution_oscillator" ){
      osc = oscillator(chaikinAD(hlc, vo),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "chaikin_volatility_sma" ){
      indicator= cbind(indicator, chaikinVolatility(hl,n = indicators_periods[index], maType = "SMA" ))
    }
    else if(indicators[i] == "chaikin_volatility_sma_oscillator"|| indicators[i] == "chaikin_volatiliy_oscillator" ){
      osc = oscillator(chaikinVolatility(hl,n = indicators_periods[index], maType = "SMA" ),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "chaikin_money_flow" || indicators[i] == "cmf"){
      indicator = cbind(indicator,CMF(hlc, vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "chaikin_money_flow_oscillator" || indicators[i] == "cmf_oscillator"){
      osc = oscillator(CMF(hlc, vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "chaikin_money_flow_sma_oscillator" || indicators[i] == "cmf_sma_oscillator"){
      osc = oscillator(SMA(CMF(hlc, vo, n = indicators_periods[index]),indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "choppy" || indicators[i] == "choppiness" || indicators[i] == "choppiness_index" ) {
      indicator= cbind(indicator,choppy_indicator_1(candles, period_choppy = indicators_periods[index]))
    }
    else if (indicators[i] == "choppy_oscillator" || indicators[i] == "choppiness_oscillator" || indicators[i] == "choppiness_index_oscillator" ) {
      osc = oscillator(choppy_indicator_1(candles, period_choppy = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "choppy_sma_oscillator" || indicators[i] == "choppiness_sma_oscillator" || indicators[i] == "choppiness_index_sma_oscillator" ) {
      osc = oscillator(SMA(choppy_indicator_1(candles, period_choppy = indicators_periods[index]),indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "choppy_ema_oscillator" || indicators[i] == "choppiness_ema_oscillator" || indicators[i] == "choppiness_index_ema_oscillator" ) {
      osc = oscillator(EMA(choppy_indicator_1(candles, period_choppy = indicators_periods[index]),indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] =="close_location_value" || indicators[i] == "clv" ){
      indicator = cbind(indicator,CLV(hlc))
    }
    else if(indicators[i] =="close_location_value_oscillator" || indicators[i] == "clv_oscillator" ){
      osc = oscillator(CLV(hlc),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "chande_momentum_oscillator_price" || indicators[i] == "cmo_price" ){
      indicator =  cbind(indicator,CMO(prices, n = indicators_periods[index])) 
    }
    else if(indicators[i] =="chande_momentum_oscillator_price_oscillator" || indicators[i] == "cmo_oscillator" ){
      osc = oscillator(CMO(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] =="chande_momentum_sma_oscillator_price_oscillator" || indicators[i] == "cmo_sma_oscillator" ){
      osc = oscillator(SMA(CMO(prices, n = indicators_periods[index]),indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] =="chande_momentum_ema_oscillator_price_oscillator" || indicators[i] == "cmo_ema_oscillator" ){
      osc = oscillator(EMA(CMO(prices, n = indicators_periods[index]),indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "chande_momentum_oscillator_volume" || indicators[i] == "cmo_volume" ){
      indicator = cbind(indicator,CMO(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] =="chande_momentum_oscillator_volume_oscillator" || indicators[i] == "cmo_volume_oscillator" ){
      osc = oscillator(CMO(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    #  This indicator cuts the matrix to have less rows, need to fix:
    # else if (indicators[i] == "correlation_trend_indicator" || indicators[i] == "cti" ){
    #   indicator = cbind(indicator, CTI(prices, n = indicators_periods[index], slope = 1))
    # }
    # else if (indicators[i] == "correlation_trend_indicator_oscillator" || indicators[i] == "cti_oscillator" ){
    #   osc = oscillator(CTI(prices, n = indicators_periods[index], slope = 1),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    else if(indicators[i] == "donchian_channel" || indicators[i] == "dc"){
      indicator = cbind(indicator, DonchianChannel(hl, n = indicators_periods[index]))
    }
    else if (indicators[i] == "donchian_channel_oscillator"){ 
      dc = DonchianChannel(hl, n = indicators_periods[index])
      osc = c()
      for (k in 1:ncol(dc)) {
        osc =cbind(osc,oscillator(dc[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    else if(indicators[i] == "dpo_prices" || indicators[i] == "detrended_oscillator_price"){
      indicator = cbind(indicator,DPO(prices, n = indicators_periods[index], percent = TRUE))
    }
    else if (indicators[i] == "dpo_prices_oscillator" || indicators[i] == "cti_oscillator" ){
      osc = oscillator(DPO(prices, n = indicators_periods[index], percent = TRUE),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "dpo_volume" || indicators[i] == "detrended_oscillator_volume"){
      indicator = cbind(indicator, DPO(vo, n = indicators_periods[index], percent = TRUE))
    }
    else if (indicators[i] == "dpo_volume_oscillator" || indicators[i] == "cti_oscillator" ){
      osc = oscillator(DPO(vo, n = indicators_periods[index], percent = TRUE),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "dvi" ){
      indicator = cbind(indicator,DVI(prices, n = indicators_periods[index], wts = c(0.8, 0.2), smooth = 3, magnitude = c(5, 100, 5), exact.multiplier = 1 ))
    }
    else if (indicators[i] == "dvi_oscillator"){ 
      dvi = DVI(prices, n = indicators_periods[index], wts = c(0.8, 0.2), smooth = 3, magnitude = c(5, 100, 5), exact.multiplier = 1 )
      osc = c()
      for (k in 1:ncol(dvi)) {
        osc =cbind(osc,oscillator(dvi[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    # This indicator gives doube the rows:
    # else if(indicators[i] == "ease_of_movement_value" || indicators[i] == "emv"){
    #   indicator = cbind(indicator,EMV(hl, vo, n = indicators_periods[index])) 
    # }
    # 
    # else if(indicators[i] == "ease_of_movement_value_oscillator" || indicators[i] == "emv_oscillator"){
    #   osc = oscillator(EMV(hl, vo, n = indicators_periods[index]),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    else if(indicators[i] == "guppy_multiple_moving_average_price" || indicators[i] == "gmma_price"){
      indicator = cbind(indicator,GMMA(prices, short = c(3, 5, 8, 10, 12, 15),long = c(30, 35, 40, 45, 50, 60),maType = "SMA"))
    }
    else if(indicators[i] == "guppy_multiple_moving_average_price_oscillator" || indicators[i] == "gmma_oscillator"){
      gmma= GMMA(prices, short = c(3, 5, 8, 10, 12, 15),long = c(30, 35, 40, 45, 50, 60),maType = "SMA")
      osc = c()
      for (k in 1:ncol(gmma)) {
        osc =cbind(osc,oscillator(gmma[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    else if(indicators[i] == "guppy_multiple_moving_average_volume" || indicators[i] == "gmma_volume"){
      indicator =cbind(indicator,GMMA(vo, short = c(3, 5, 8, 10, 12, 15),long = c(30, 35, 40, 45, 50, 60),maType = "SMA"))
    }
    else if(indicators[i] == "guppy_multiple_moving_average_volume_oscillator" || indicators[i] == "gmma_volume_oscillator"){
      gmma= GMMA(vo, short = c(3, 5, 8, 10, 12, 15),long = c(30, 35, 40, 45, 50, 60),maType = "SMA")
      osc = c()
      for (k in 1:ncol(gmma)) {
        osc =cbind(osc,oscillator(gmma[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    else if(indicators[i] == "know_sure_thing" || indicators[i] == "kst"){
      indicator = cbind(indicator,KST(prices, n = indicators_periods[index], nROC = 10, nSig = 9)) 
    }
    else if(indicators[i] == "know_sure_thing_oscillator" || indicators[i] == "kst_oscillator"){
      kst_p = KST(prices, n = indicators_periods[index], nROC = 10, nSig = 9)
      osc = c()
      for (k in 1:ncol(kst_p)) {
        osc =cbind(osc,oscillator(kst_p[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc)
    }
    else if (indicators[i] == "macd" || indicators[i] == "macd_price") {
      #This function need the indicator periods to be different, the choices are arbitrary:
      indicator = cbind(indicator,MACD(prices,nFast = indicators_periods[index]+10, nSlow = indicators_periods[index], nSig = indicators_periods[index]+5))
    }
    else if (indicators[i] == "macd_oscillator"){ 
      mcad = MACD(prices,nFast = indicators_periods[index]+10, nSlow = indicators_periods[index], nSig = indicators_periods[index]+5)
      osc = c()
      for (k in 1:ncol(mcad)) {
        osc =cbind(osc,oscillator(mcad[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    else if (indicators[i] == "macd_volume") {
      indicator = cbind(indicator,MACD(vo,nFast = indicators_periods[index]+10, nSlow = indicators_periods[index], nSig = indicators_periods[index]+5)) 
    }
    else if (indicators[i] == "macd_volume_oscillator"){ 
      mcad = MACD(vo, nFast = indicators_periods[index]+10, nSlow = indicators_periods[index], nSig = indicators_periods[index]+5)
      osc = c()
      for (k in 1:ncol(mcad)) {
        osc =cbind(osc,oscillator(mcad[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    else if(indicators[i] == "money_flow_index" || indicators[i] == "mfi"){
      indicator = cbind(indicator,MFI(hlc, vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "money_flow_index_oscillator" || indicators[i] == "mfi_oscillator"){
      osc = oscillator(MFI(hlc, vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "money_flow_index_sma_oscillator" || indicators[i] == "mfi_sma_oscillator"){
      osc = oscillator(SMA(MFI(hlc, vo, n = indicators_periods[index]),indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "money_flow_index_ema_oscillator" || indicators[i] == "mfi_ema_oscillator"){
      osc = oscillator(EMA(MFI(hlc, vo, n = indicators_periods[index]),indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "on_balance_volume" || indicators[i] == "obv"){
      indicator = cbind(indicator,OBV(prices, vo)) 
    }
    else if(indicators[i] == "on_balance_volume_oscillator" || indicators[i] == "obv_oscillator"){
      osc = oscillator(OBV(prices, vo),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if(indicators[i] == "pbands" || indicators[i] == "prices_band_dow"){
      indicator= cbind(indicator,PBands(prices, n = indicators_periods[index], sd = 2, fastn = 2, centered = FALSE, lavg = FALSE))
    }
    else if (indicators[i] == "pbands_oscillator"){ 
      pbands = PBands(prices, n = indicators_periods[index], sd = 2, fastn = 2, centered = FALSE, lavg = FALSE)
      osc = c()
      for (k in 1:ncol(pbands)) {
        osc =cbind(osc,oscillator(pbands[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    else if (indicators[i] == "roc_continuous_price") { 
     indicator = cbind(indicator,ROC(prices, n = indicators_periods[index], type = "continuous")) 
    }
    else if(indicators[i] == "roc_continuous_price_oscillator" ){
      osc = oscillator(ROC(prices, n = indicators_periods[index], type = "continuous"),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "roc_discrete_price") { 
      indicator = cbind(indicator,ROC(prices, n = indicators_periods[index], type = "discrete")) 
    }
    else if(indicators[i] == "roc_discrete_price_oscillator" ){
      osc = oscillator(ROC(prices, n = indicators_periods[index], type = "discrete"),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if (indicators[i] == "momentum_price" || indicators[i] == "mom") { 
      indicator = cbind(indicator,momentum(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "momentum_price_oscillator" ){
      osc = oscillator(momentum(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "momentum_price_sma_oscillator" ){
      osc = oscillator(SMA(momentum(prices, n = indicators_periods[index]),indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "momentum_price_ema_oscillator" ){
      osc = oscillator(EMA(momentum(prices, n = indicators_periods[index]),indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "momentum_volume" || indicators[i] == "mom_volume") { 
      indicator = cbind(indicator,momentum(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "momentum_volume_oscillator" ){
      osc = oscillator(momentum(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "relative_strength_index" || indicators[i] == "rsi") { 
      indicator= cbind(indicator,RSI(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "relative_strength_index_oscillator" ){
      osc = oscillator(RSI(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "relative_strength_index_sma_oscillator" ){
      osc = oscillator(SMA(RSI(prices, n = indicators_periods[index]),n = indicators_periods[index]) ,indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "relative_strength_index_ema_oscillator" ){
      osc = oscillator(EMA(RSI(prices, n = indicators_periods[index]),n = indicators_periods[index]) ,indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "relative_strength_index_volume" || indicators[i] == "rsi_volume") { 
      indicator= cbind(indicator,RSI(vo, n = indicators_periods[index]))
    }
    
    else if(indicators[i] == "relative_strength_index_volume_oscillator" ){
      osc = oscillator(RSI(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if(indicators[i] == "run_percent_rank_prices" || indicators[i] == "rpr_prices"){
      indicator = cbind(indicator,runPercentRank(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_percent_rank_prices_oscillator" ){
      osc = oscillator(runPercentRank(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if(indicators[i] == "run_percent_rank_volume" || indicators[i] == "rpr_volume"){
      indicator = cbind(indicator,runPercentRank(vo, n = indicators_periods[index])) 
     
    }
    else if(indicators[i] == "run_percent_rank_volume_oscillator" ){
      osc = oscillator(runPercentRank(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "run_sum_prices"){
      indicator = cbind(indicator,runSum(prices, n = indicators_periods[index])) 
    }
    else if(indicators[i] == "run_sum_prices_oscillator" ){
      osc = oscillator(runSum(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "run_sum_volume"){
      indicator = cbind(indicator,runSum(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_sum_volume_oscillator" ){
      osc = oscillator(runSum(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
  
    else if(indicators[i] == "run_min_prices"){
      indicator  = cbind(indicator,runMin(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_min_oscillator" ){
      osc = oscillator(runMin(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if(indicators[i] == "run_min_volume"){
      indicator = cbind(indicator,runMin(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_min_volume_oscillator" ){
      osc = oscillator(runMin(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if(indicators[i] == "run_max_prices"){
      indicator = cbind(indicator,runMax(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_max_oscillator" ){
      osc = oscillator(runMax(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if(indicators[i] == "run_max_volume"){
      indicator = cbind(indicator,runMax(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_max_voulme_oscillator" ){
      osc = oscillator(runMax(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if(indicators[i] == "run_mean_prices"){
      indicator = cbind(indicator,runMean(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_mean_oscillator" ){
      osc = oscillator(runMean(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if(indicators[i] == "run_mean_volume"){
      indicator = cbind(indicator,runMean(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_mean_oscillator" ){
      osc = oscillator(runMean(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if(indicators[i] == "run_median_prices"){
      indicator= cbind(indicator,runMedian(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_median_oscillator" ){
      osc = oscillator(runMedian(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if(indicators[i] == "run_median_volume"){
      indicator = cbind(indicator,runMedian(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_median_volume_oscillator" ){
      osc = oscillator(runMedian(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    # else if(indicators[i] == "run_covariances_prices"){
    #   indicator = cbind(indicator,runCov(prices, n = indicators_periods[index]))
    # }
    # else if(indicators[i] == "run_covariances_oscillator" ){
    #   osc = oscillator(runCov(prices, n = indicators_periods[index]),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    # else if(indicators[i] == "run_covariances_volume"){
    #   indicator = cbind(indicator,runCov(vo, n = indicators_periods[index]))
    # }
    # else if(indicators[i] == "run_covariances_volume_oscillator" ){
    #   osc = oscillator(runCov(vo, n = indicators_periods[index]),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    # else if(indicators[i] == "run_correlations_prices"){
    #   indicator = cbind(indicator,runCor(prices, n = indicators_periods[index]))
    # }
    # else if(indicators[i] == "run_correlations_oscillator" ){
    #   osc = oscillator(runCor(prices, n = indicators_periods[index]),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    # else if(indicators[i] == "run_correlations_volume"){
    #   indicator = cbind(indicator,runCor(vo, n = indicators_periods[index]))
    # }
    # else if(indicators[i] == "run_correlations_volume_oscillator" ){
    #   osc = oscillator(runCor(vo, n = indicators_periods[index]),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    # else if(indicators[i] == "run_variances_prices"){
    #   indicator = cbind(indicator,runVar(prices, n = indicators_periods[index]))
    # }
    # else if(indicators[i] == "run_variances_oscillator" ){
    #   osc = oscillator(runVar(prices, n = indicators_periods[index]),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    # else if(indicators[i] == "run_variances_volume"){
    #   indicator = cbind(indicator,runVar(vo, n = indicators_periods[index]))
    # }
    # else if(indicators[i] == "run_variances_volume_oscillator" ){
    #   osc = oscillator(runVar(vo, n = indicators_periods[index]),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    else if(indicators[i] == "run_standard_deviations_prices"){
      indicator = cbind(indicator,runSD(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_standard_deviations_oscillator" ){
      osc = oscillator(runSD(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "run_standard_deviations_volume"){
      indicator = cbind(indicator,runSD(vo, n = indicators_periods[index]))
      
    }
    else if(indicators[i] == "run_standard_deviations_volume_oscillator" ){
      osc = oscillator(runSD(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "run_median_mean_absolute_deviations_prices"){
      indicator = cbind(indicator,runMAD(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_median_mean_absolute_deviations_oscillator" ){
      osc = oscillator(runMAD(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "run_median_mean_absolute_deviations_volume"){
      indicator = cbind(indicator,runMAD(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "run_median_mean_absolute_deviations_volume_oscillator" ){
      osc = oscillator(runMAD(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "wilder_sum_prices"){
      indicator = cbind(indicator,wilderSum(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "wilder_sum_prices_oscillator" ){
      osc = oscillator(wilderSum(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if(indicators[i] == "wilder_sum_volume"){
      indicator = cbind(indicator,wilderSum(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "wilder_sum_volume_oscillator" ){
      osc = oscillator(wilderSum(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if(indicators[i] == "stop_and_reverse" || indicators[i] == "sar"){
      indicator = cbind(indicator,SAR(hl, accel = c(0.02, 0.2)))
    }
    else if(indicators[i] == "stop_and_reverse_oscillator" ){
      osc = oscillator(SAR(hl, accel = c(0.02, 0.2)),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "simple_moving_averages_price" || indicators[i] == "sma_price"){
      indicator = cbind(indicator,SMA(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "simple_moving_averages_price_oscillator" ){
      osc = oscillator(SMA(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if (indicators[i] == "simple_moving_averages_volume" || indicators[i] == "sma_volume"){ 
      indicator = cbind(indicator,SMA(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "simple_moving_averages_volume_oscillator" ){
      osc = oscillator(SMA(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    
    else if (indicators[i] == "exponential_moving_averages_prices" || indicators[i] == "ema_prices"){ 
      indicator = cbind(indicator,EMA(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "exponential_moving_averages_prices_oscillator" ){
      osc = oscillator(EMA(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "exponential_moving_averages_volume" || indicators[i] == "ema_volume"){ 
      indicator = cbind(indicator,EMA(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "exponential_moving_averages_volume_oscillator" ){
      osc = oscillator(EMA(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "double_exponential_moving_average_prices" || indicators[i] == "dema_prices"){ 
      indicator = cbind(indicator,DEMA(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "double_exponential_moving_average_prices_oscillator" ){
      osc = oscillator(DEMA(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "double_exponential_moving_average_volume" || indicators[i] == "dema_volume"){ 
      indicator = cbind(indicator,DEMA(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "double_exponential_moving_average_volume_oscillator" ){
      osc = oscillator(DEMA(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "weighted_moving_average_prices" || indicators[i] == "wma_prices"){ 
      indicator = cbind(indicator,WMA(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "weighted_moving_average_prices_oscillator" ){
      osc = oscillator(WMA(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "weighted_moving_average_volume" || indicators[i] == "wma_volume"){ 
      indicator = cbind(indicator,WMA(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "weighted_moving_average_volume_oscillator" ){
      osc = oscillator(WMA(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "elastic_volume_weighted_moving_average" || indicators[i] == "evwma"){ 
      indicator = cbind(indicator,EVWMA(prices, vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "elastic_volume_weighted_moving_average_oscillator" ){
      osc = oscillator(EVWMA(prices,vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "zero_lag_exponential_moving_average_prices" || indicators[i] == "zlema_prices"){ 
      indicator = cbind(indicator,ZLEMA(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "zero_lag_exponential_moving_average_prices_oscillator" ){
      osc = oscillator(ZLEMA(prices, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "zero_lag_exponential_moving_average_volume" || indicators[i] == "zlema_volume"){ 
      indicator = cbind(indicator,ZLEMA(vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "zero_lag_exponential_moving_average_prices_oscillator" ){
      osc = oscillator(ZLEMA(vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "volume_weighted_moving_average_prices" || indicators[i] == "evwma"){ 
      indicator = cbind(indicator,VWAP(prices, vo, n = indicators_periods[index]))
    }
    else if(indicators[i] == "volume_weighted_moving_average_prices_oscillator" ){
      osc = oscillator(VWAP(prices,vo, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    # else if (indicators[i] == "variable_length_moving_average_prices" || indicators[i] == "vma_prices"){ 
    #   indicator = cbind(indicator,VMA(prices,w=c(0.25,0.5,0.75),ratio = 1, n = indicators_periods[index]))
    # }
    # else if(indicators[i] == "variable_length_moving_average_prices_oscillator" ){
    #   osc = oscillator(VMA(prices,ratio=1, n = indicators_periods[index]),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    # else if (indicators[i] == "variable_length_moving_average_volume" || indicators[i] == "vma_volume"){ 
    #   indicator = cbind(indicator,VMA(vo, ratio = 1, n = indicators_periods[index]))
    # }
    # else if(indicators[i] == "variable_length_moving_average_volume_oscillator" ){
    #   osc = oscillator(VMA(vo,ratio = 1, n = indicators_periods[index]),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    else if (indicators[i] == "hull_moving_average_prices" || indicators[i] == "hma_prices"){ 
      indicator = cbind(indicator,HMA(prices, ratio = 1, n = indicators_periods[index]))
    }
    else if(indicators[i] == "hull_moving_average_prices_oscillator" ){
      osc = oscillator(HMA(prices,ratio=1, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "hull_moving_average_volume" || indicators[i] == "hma_volume"){ 
      indicator = cbind(indicator,HMA(vo, ratio = 1, n = indicators_periods[index]))
    }
    else if(indicators[i] == "hull_moving_average_volume_oscillator" ){
      osc = oscillator(HMA(vo,ratio=1, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "arnaud_legoux_moving_average_prices" || indicators[i] == "alma_prices"){ 
      indicator = cbind(indicator,ALMA(prices, ratio = 1, n = indicators_periods[index]))
    }
    else if(indicators[i] == "arnaud_legoux_moving_average_prices_oscillator" ){
      osc = oscillator(ALMA(prices,ratio=1, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "arnaud_legoux_moving_average_volume" || indicators[i] == "alma_volume"){ 
      indicator = cbind(indicator,ALMA(vo, ratio = 1, n = indicators_periods[index]))
    }
    else if(indicators[i] == "arnaud_legoux_moving_average_volume_oscillator" ){
      osc = oscillator(ALMA(vo,ratio=1, n = indicators_periods[index]),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "stochastic" ){ 
      indicator = cbind(indicator,stoch(hlc, nFastK = indicators_periods[index]))
    }
    else if (indicators[i] == "stochastic_momentum_index" || indicators[i] == "smi"){ 
      indicator = cbind(indicator,SMI(hlc, n = indicators_periods[index], nFast = indicators_periods[index]+2, nSlow = indicators_periods[index]+5, nSig = indicators_periods[index]))
    }
    else if(indicators[i] == "stochastic_momentum_index_oscillator" ){
      smi_p = SMI(hlc, n = indicators_periods[index], nFast = indicators_periods[index]+2, nSlow = indicators_periods[index]+5, nSig = indicators_periods[index])
      osc = c()
      for (k in 1:ncol(smi_p)) {
        osc =cbind(osc,oscillator(smi_p[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    else if (indicators[i] == "trend_detection" || indicators[i] == "td") { 
      indicator = cbind(indicator,TDI(prices, n = indicators_periods[index]))
    }
    else if(indicators[i] == "trend_detection_oscillator" ){
      tdi_p = TDI(prices, n = indicators_periods[index])
      osc = c()
      for (k in 1:ncol(tdi_p)) {
        osc =cbind(osc,oscillator(tdi_p[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    else if (indicators[i] == "trix") {
      indicator = cbind(indicator,TRIX(prices, n = indicators_periods[index], nSig = indicators_periods[index]+2))
    }
    else if(indicators[i] == "trix_oscillator" ){
      trix_p = TRIX(prices, n = indicators_periods[index], nSig = indicators_periods[index]+2)
      osc = c()
      for (k in 1:ncol(trix_p)) {
        osc =cbind(osc,oscillator(trix_p[,k], periods = indicators_periods[index])) 
      }
      indicator = cbind(indicator,osc) 
    }
    else if (indicators[i] == "ultimate_oscillator" || indicators[i] == "uo") { 
      indicator = cbind(indicator,ultimateOscillator(hlc, n = c(indicators_periods[index],2*indicators_periods[index],3*indicators_periods[index]),wts = c(3,2,1)))
    }
    else if(indicators[i] == "ultimate_oscillator_oscillator" ){
      osc = oscillator(ultimateOscillator(hlc, n = c(indicators_periods[index],2*indicators_periods[index],3*indicators_periods[index]),wts = c(3,2,1)))
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "vertical_horizontal_filter" || indicators[i] == "vhf") { 
      indicator= cbind(indicator,VHF(prices, n = indicators_periods[index]))
    }
    else if (indicators[i] == "volatility_close") {
      indicator = cbind(indicator,volatility(prices, n = indicators_periods[index], calc = "close")) 
    }
    else if (indicators[i] == "volatility_garman_klass") { # Garman and Klass estimator that allows for opening gaps
      indicator = cbind(indicator,volatility(candles[,-c(1)], n = indicators_periods[index], calc = "garman.klass")) 
    }
    else if(indicators[i] == "volatility_garman_klass_oscillator" ){
      osc = oscillator(volatility(candles[,-c(1)], n = indicators_periods[index], calc = "garman.klass"),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "volatility_parkinson") {
      indicator = cbind(indicator,volatility(candles, n = indicators_periods[index], calc = "parkinson")) 
    }
    else if(indicators[i] == "volatility_parkinson_oscillator" ){
      osc = oscillator(volatility(candles, n = indicators_periods[index], calc = "parkinson"),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "volatility_rogers_satchell") {
      indicator= cbind(indicator,volatility(candles[,-c(1)], n = indicators_periods[index], calc = "rogers.satchell")) 
    }
    else if(indicators[i] == "volatility_rogers_satchell_oscillator" ){
      osc = oscillator(volatility(candles[,-c(1)], n = indicators_periods[index], calc = "rogers.satchell"),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "volatility_garman_klass_yang_zhang") {
      indicator = cbind(indicator,volatility(candles, n = indicators_periods[index], calc = "gk.yz")) 
    }
    else if(indicators[i] == "volatility_garman_klass_yang_zhang_oscillator" ){
      osc = oscillator(volatility(candles, n = indicators_periods[index], calc = "gk.yz"),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "volatility_yang_zhang") {
      indicator = cbind(indicator,volatility(candles, n = indicators_periods[index], calc = "yang.zhang")) 
    }
    else if(indicators[i] == "volatility_yang_zhang_oscillator" ){
      osc = oscillator(volatility(candles, n = indicators_periods[index], calc = "yang.zhang"),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "volatility_close_mean0") {
      indicator = cbind(indicator,volatility(candles, n = indicators_periods[index], calc = "close", mean0=TRUE))
    }
    else if(indicators[i] == "volatility_close_mean0_oscillator" ){
      osc = oscillator(volatility(candles, n = indicators_periods[index], calc = "close", mean0=TRUE),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "volatility_garman_klass_mean0") { # Garman and Klass estimator that allows for opening gaps
      indicator = cbind(indicator,volatility(candles, n = indicators_periods[index], calc = "garman.klass", mean0=TRUE))
    }
    else if(indicators[i] == "volatility_garman_klass_mean0_oscillator" ){
      osc = oscillator(volatility(candles, n = indicators_periods[index], calc = "garman.klass", mean0=TRUE),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "volatility_parkinson_mean0") {
      indicator = cbind(indicator,volatility(candles, n = indicators_periods[index], calc = "parkinson", mean0=TRUE))
    }
    else if(indicators[i] == "volatility_parkinson_mean0_oscillator" ){
      osc = oscillator(volatility(candles, n = indicators_periods[index], calc = "parkinson", mean0=TRUE),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "volatility_rogers_satchell_mean0") {
      indicator = cbind(indicator,volatility(candles[,-c(1)], n = indicators_periods[index], calc = "rogers.satchell", mean0=TRUE)) 
    }
    else if(indicators[i] == "volatility_rogers_satchell_mean0_oscillator" ){
      osc = oscillator(volatility(candles[,-c(1)], n = indicators_periods[index], calc = "rogers.satchell", mean0=TRUE),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    # else if (indicators[i] == "volatility_garman_klass_yang_zhang_mean0") {
    #   indicator = cbind(indicator,volatility(candles, n = indicators_periods[index], calc = "gk.yz", mean0=TRUE))
    # }
    # else if(indicators[i] == "volatility_garman_klass_yang_zhang_mean0_oscillator" ){
    #   osc = oscillator(volatility(candles, n = indicators_periods[index], calc = "gk.yz", mean0=TRUE),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    # else if (indicators[i] == "volatility_yang_zhang_mean0") {
    #   indicator = cbind(indicator,volatility(candles, n = indicators_periods[index], calc = "yang.zhang", mean0=TRUE)) 
    # }
    # else if(indicators[i] == "volatility_yang_zhang_mean0_oscillator" ){
    #   osc = oscillator(volatility(candles, n = indicators_periods[index], calc = "yang.zhang", mean0=TRUE),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    else if (indicators[i] == "williams_accumulation_distribution" || indicators[i] == "williams_ad") {
      indicator = cbind(indicator,williamsAD(hlc))
    }
    else if(indicators[i] == "williams_accumulation_distribution_oscillator" ){
      osc = oscillator(williamsAD(hlc),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    else if (indicators[i] == "williams_percent_range" || indicators[i] == "wpr") {
      indicator = cbind(indicator,WPR(hlc, n = indicators_periods[index]))
    }
    else if (indicators[i] == "zig_zag" || indicators[i] == "zigzag") {
      indicator = cbind(indicator,ZigZag(hl))
    }
    else if(indicators[i] == "zig_zag_oscillator" ){
      osc = oscillator(ZigZag(hl),indicators_periods[index])
      indicator= cbind(indicator,osc)
    }
    ########################################### quantmod ################################################ quantmod ####################################    
    # else if (indicators[i] == "calculate_percent_change_open" || indicators[i] == "delt_open") {
    #   indicator = cbind(indicator,Delt(open)) 
    # }
    # else if(indicators[i] == "calculate_percent_change_open_oscillator" ){
    #   osc = oscillator(Delt(open),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    # else if (indicators[i] == "calculate_percent_change_open_k1" || indicators[i] == "delt_open_k1") {
    #   indicator = cbind(indicator,Delt(open, k = 1))
    # }
    # else if(indicators[i] == "calculate_percent_change_open_k1_oscillator" ){
    #   osc = oscillator(Delt(open,k=1),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    # else if (indicators[i] == "calculate_percent_change_open_arithmetic" || indicators[i] == "delt_open_arithmetic") {
    #   indicator = cbind(indicator,Delt(open, type = "arithmetic"))
    # }
    # else if(indicators[i] == "calculate_percent_change_open_arithmetic_oscillator" ){
    #   osc = oscillator(Delt(open, type = "arithmetic"),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    # else if (indicators[i] == "calculate_percent_change_open_log" || indicators[i] == "delt_open_log") {
    #   indicator = cbind(indicator,Delt(open, type = "log"))
    # }
    # else if(indicators[i] == "calculate_percent_change_open_log_oscillator" ){
    #   osc = oscillator(Delt(open, type = "log"),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    # else if (indicators[i] == "calculate_percent_change_open_close" || indicators[i] == "delt_open_close") {
    #   indicator = cbind(indicator,Delt(open, close))
    # }
    # else if(indicators[i] == "calculate_percent_change_open_close_oscillator" ){
    #   osc = oscillator(Delt(open,close),indicators_periods[index])
    #   indicator= cbind(indicator,osc)
    # }
    ########################## End of Model Indicator Matrix Function ################################################################################# 
    #indicator = zero_to_one(indicator)
    #indicator_scaled = (indicator - min(indicator))/(max(indicator) - min(indicator)) #why is indicator_scaled commented out
    #model = cbind(model,indicator) # ,indicator_scaled)
  }
    
  #return(model)
  return(indicator)
}
