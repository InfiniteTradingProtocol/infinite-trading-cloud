import redis

def addOrReplaceInstruction(profile=None,
                            symbol=None,
                            side="hold",
                            targetPrice=None,
                            stopLoss=None,
                            stopLossLimitOrders='T',
                            marketThreshold=None,
                            marketPercent=.25,
                            maximumTrade='a',
                            orderDepthTarget=.67,
                            orderDepthSearchRange=25,
                            orderMultiplier=1):
    redisCon = redis.Redis(host='localhost', port=46379, password='angelLearnsRedis123')
    if profile == None or symbol == None or targetPrice == None or stopLoss == None or marketThreshold == None:
        raise ValueError("profile, symbol, targetPrice, stopLoss, and marketThreshold are required")
    elif orderMultiplier < 1:
        raise ValueError("orderMultiplier must be greater than or equal to 1")
    elif orderDepthSearchRange < 1 or orderDepthSearchRange > 50:
        raise ValueError("orderDepthSearchRange must be between 1 and 50")
    elif marketPercent <= 0 or marketPercent > 1:
        raise ValueError("marketPercent must be > 0 and <= 1")
    else:
        #print(str(datetime.datetime.now()) + " - " + "The value of profile is:" + profile)
        if (redisCon.hget(profile+"instruction", "side") != None and side != redisCon.hget(profile+"instruction", "side").decode("utf-8")):
            redisCon.hset(profile+"instruction", "orderSideChange", 1)
        else:
            redisCon.hset(profile+"instruction", "orderSideChange", 0)
        redisCon.hmset(profile+"instruction", {"symbol":symbol,
                                                    "side":side,
                                                    "targetPrice":targetPrice,
                                                    "stopLoss":stopLoss,
                                                    "stopLossLimitOrders":stopLossLimitOrders,
                                                    "marketThreshold":marketThreshold,
                                                    "marketPercent":marketPercent,
                                                    "maximumTrade":maximumTrade,
                                                    "orderDepthTarget":orderDepthTarget,
                                                    "orderDepthSearchRange":int(orderDepthSearchRange),
                                                    "orderMultiplier":orderMultiplier,
                                                    "state":"newInstruction"
                                                    }
                            )
