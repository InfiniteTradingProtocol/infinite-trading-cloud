signals_from_probabilities = function(probabilities,model) {
                buy_thresholds =  c(0.50,0.50,0.50,0.53,0.55,0.57,0.60,0.65,0.70,0.80,0.80)
                sell_thresholds = c(0.10,0.20,0.30,0.33,0.35,0.37,0.40,0.35,0.30,0.20,0.10)
                probabilities = na.omit(probabilities)
                n_prob = length(probabilities)

                signals = rep(-1,length(buy_thresholds))
                signals_close = rep(-1,length(buy_thresholds))
                for (k in 1:(n_prob)) {
                        for (j in 1:length(signals)) {
                                if (probabilities[k] >= buy_thresholds[j]) { signals[j] = 1 }
                                else if (probabilities[k] <= sell_thresholds[j]) { signals[j] = 0 }
                                if (k > 1) {
                                        if (probabilities[k-1] >= buy_thresholds[j]) { signals_close[j] = 1 }
                                        else if (probabilities[k-1] <= sell_thresholds[j]) { signals_close[j] = 0 }
                                }
                        }
                }
                print("signals"); print(signals); print("signals close"); print(signals_close)
                for (q in 1:length(signals)) {
                        if (signals[q] == -1) {
                                last_db_signal = get_signals(model=model,buy_threshold=buy_thresholds[q],sell_threshold=sell_thresholds[q],candle_close=FALSE)
                                if (last_db_signal == -1) {
                                        if (probabilities[n_prob] >= 0.50) { signals[q] = 1 }
                                }
                                else {
                                        signals[q] = last_db_signal
                                        print(paste0("Warning: model ",model," last signal is -1, estimating the actual signal with the last database signal"))
                                }
                        }
                      if (signals_close[q] == -1) {
                                last_db_signal = get_signals(model=model,buy_threshold=buy_thresholds[q],sell_threshold=sell_thresholds[q],candle_close=TRUE)
                                if (last_db_signal == -1) {
                                        if (probabilities[n_prob-1] >= 0.50) { signals_close[q] = 1 }
                                        else { signals_close[q] = 0 }
                                        print(paste0("Warning: model ",models[i]," last database signal is -1, estimating the candle close signal with the last probability and 50% threshold"))
                                }
                                else {
                                        signals_close[q] = last_db_signal
                                        print(paste0("Warning: model ",models[i]," last signal is -1, estimating the actual signal with the last database signal"))
                               }
                       }
                }
                discord(msg=paste0("model: ",model," probability: ", prob, " / old probability: ",old_prob),channel="#signals")
                discord(msg=paste0("buy thresholds:",paste(buy_thresholds,collapse=",")),channel="#signals")
                discord(msg=paste0("sell thresholds:",paste(sell_thresholds,collapse=",")),channel="#signals")
                discord(msg=paste0("signals: ",paste(signals,collapse=",")),channel="#signals")
                discord(msg=paste0("signals close: ",paste(signals_close,collapse=",")),channel="#signals")
                set_signals(model=model,buy_threshold = buy_thresholds,sell_threshold= sell_thresholds,signal_close=signals_close,signal=signals)
}
