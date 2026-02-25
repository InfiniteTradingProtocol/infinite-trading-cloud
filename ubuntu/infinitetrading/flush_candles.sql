USE infinitetrading;

TRUNCATE TABLE `coinbase_BTC-USD_6h`;
TRUNCATE TABLE `coinbase_BTC-USD_1d`;
TRUNCATE TABLE `coinbase_ETH-USD_6h`;
TRUNCATE TABLE `coinbase_ETH-USD_1d`;
TRUNCATE TABLE `coinbase_SNX-USD_6h`;
TRUNCATE TABLE `coinbase_OP-USD_6h`;
TRUNCATE TABLE `coinbase_AERO-USD_6h`;
TRUNCATE TABLE `coinbase_ARB-USD_6h`;
TRUNCATE TABLE `coinbase_LINK-USD_6h`;
TRUNCATE TABLE `coinbase_MORPHO-USD_6h`;
TRUNCATE TABLE `coinbase_POL-USD_6h`;
TRUNCATE TABLE `coinbase_SOL-USD_6h`;
TRUNCATE TABLE `coinbase_VELO-USD_15m`;
TRUNCATE TABLE `coinbase_VELO-USD_1d`;

SELECT 'All candle tables flushed successfully' AS Status;
