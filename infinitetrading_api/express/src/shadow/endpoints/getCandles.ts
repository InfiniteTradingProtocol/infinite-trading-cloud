/**
 * shadow/endpoints/getCandles.ts — Node port of R gateway's getCandles.R
 * (proxies to plumber-api port 8002 -> real implementation in src/api/db.R's
 * getCandles()).
 *
 * PARITY NOTES:
 *  - Uses the SAME "frontend" literal apiKey scheme as getTotalYield/
 *    getEstimatedAnualYield/getAllYields (NOT basic_check's UUID validation) —
 *    confirmed by getCandlesHandler's `if (apiKey != "frontend") return(fail)`.
 *  - Validates exchange/timeframe/pair BEFORE the DB query, matching R's
 *    is_safe_candle_exchange/is_safe_candle_timeframe/is_safe_candle_pair
 *    regexes exactly (src/api/helpers/apiHelpers.R):
 *      exchange:  ^[A-Za-z0-9_]+$
 *      pair:      ^[A-Za-z0-9]+-[A-Za-z0-9]+$
 *      timeframe: ^[0-9]+[mhdw]$ (case-insensitive)
 *  - bars_back defaults to 200 (the gateway handler's own default), validated
 *    directly against [1, 1000] — NOT clamped, rejected with a 400 fail if
 *    out of range (confirmed live: bars_back=5000 -> 400 "Invalid bars_back").
 *    db.R's getCandles() has its own internal clamp/default (350, cap 1000),
 *    but that function is only reachable via the plumber-api (port 8002)
 *    process behind the gateway, which always receives a bars_back value
 *    from the gateway handler, so its clamp branch is effectively dead from
 *    the public API's perspective — replicated behavior matches the gateway
 *    handler, not db.R's internal fallback.
 *  - Table name: `${exchange}_${PAIR (uppercase)}_${timeframe (lowercase)}`
 *    (all pre-validated by the regexes above, so string interpolation into
 *    the identifier is safe — mirrors R's dbQuoteIdentifier usage exactly).
 *  - Column order from DB: [id?, time, low, high, open, close, volume] (R
 *    reads columns 2-7 positionally: OHLC[,2]=time, [,3]=low, [,4]=high,
 *    [,5]=open, [,6]=close, [,7]=volume) — replicated via `SELECT *` and
 *    reading the same 6 positional columns (index 1-6, since MySQL rows are
 *    returned as plain objects here we rely on the query's column order,
 *    confirmed by inspecting the live table schema below).
 *  - Time is converted from unix seconds to an ISO string sorted ascending
 *    (R: `as.POSIXct(...)`, then `order(OHLC$time)`) — replicated with a JS
 *    Date conversion + ascending sort by time.
 *  - On no candles found: returns `{}` empty object list in R's plumber
 *    serialization of an empty/NULL data.frame — TODO verify exact wire
 *    shape via live curl before treating this as final; not yet confirmed.
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../../db';

const router = Router();

function isSafeCandleExchange(exchange: string): boolean {
  return /^[A-Za-z0-9_]+$/.test(exchange);
}

function isSafeCandlePair(pair: string): boolean {
  return /^[A-Za-z0-9]+-[A-Za-z0-9]+$/.test(pair);
}

function isSafeCandleTimeframe(timeframe: string): boolean {
  return /^[0-9]+[mhdw]$/i.test(timeframe);
}

router.get('/getCandles', async (req: Request, res: Response) => {
  const apiKey = String(req.query.apiKey || '');
  if (apiKey !== 'frontend') {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid API Key'] });
  }

  const exchange = String(req.query.exchange || 'coinbase');
  const timeframe = String(req.query.timeframe || '6h');
  const pair = String(req.query.pair || 'BTC-USD');
  const barsBackRaw = req.query.bars_back;

  if (!isSafeCandleExchange(exchange) || !isSafeCandleTimeframe(timeframe) || !isSafeCandlePair(pair)) {
    return res.json({ status: ['fail'], status_code: [400], message: ['Invalid candle parameters'] });
  }

  let barsBack = parseInt(String(barsBackRaw ?? '200'), 10);
  if (Number.isNaN(barsBack) || barsBack <= 0 || barsBack > 1000) {
    return res.json({ status: ['fail'], status_code: [400], message: ['Invalid bars_back'] });
  }

  const tableName = `${exchange.toLowerCase()}_${pair.toUpperCase()}_${timeframe.toLowerCase()}`;

  try {
    // NOTE: node-mysql's text protocol returns FLOAT columns truncated to ~6
    // significant digits (e.g. 79833.859375 -> "79833.9"), unlike R's DBI
    // driver which reads the full float32 value. Casting to DOUBLE via SQL
    // forces MySQL to return the exact stored float32 bit pattern widened to
    // double precision (matches what R sees), which we then round the same
    // way jsonlite does (see below).
    const rows = await dbQuery(
      `SELECT time, CAST(low AS DOUBLE) AS low, CAST(high AS DOUBLE) AS high, ` +
        `CAST(open AS DOUBLE) AS open, CAST(close AS DOUBLE) AS close, CAST(volume AS DOUBLE) AS volume ` +
        `FROM \`${tableName}\` ORDER BY time DESC LIMIT ${barsBack}`
    );

    if (!rows || rows.length === 0) {
      return res.json({});
    }

    // Confirmed live (curl) that `time` is serialized back out as a raw unix
    // seconds integer, NOT an ISO string — R's POSIXct conversion is only an
    // internal step used for sorting; jsonlite re-serializes it as a number.
    // OHLCV values are rounded to 4 DECIMAL PLACES (not significant digits) —
    // same jsonlite default behavior confirmed for getTotalYield/
    // getEstimatedAnualYield (see yields.ts's toSignificantDigits, misleadingly
    // named but actually fixed-decimal rounding).
    const round4 = (n: number) => Math.round(n * 10000) / 10000;
    const candles = rows.map((row) => ({
      time: Number(row.time),
      low: round4(Number(row.low)),
      high: round4(Number(row.high)),
      open: round4(Number(row.open)),
      close: round4(Number(row.close)),
      volume: round4(Number(row.volume)),
    }));

    // Ascending by time, matching R's order(OHLC$time).
    candles.sort((a, b) => a.time - b.time);

    return res.json(candles);
  } catch (e: any) {
    console.log(`error fetching candles: ${e.message}`);
    return res.json({});
  }
});

export default router;
