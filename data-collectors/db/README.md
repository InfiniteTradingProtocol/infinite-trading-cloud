#To create the tables do this:

CREATE TABLE `infinitetrading`.`messages` (
  `platform` VARCHAR(225) NOT NULL,
  `channel` VARCHAR(225) NOT NULL,
  `message` VARCHAR(225) NOT NULL,
  PRIMARY KEY (`message`));

CREATE TABLE `infinitetrading`.`BTC-USD_6h` (
  `id` INT NOT NULL,
  `time` VARCHAR(225) NOT NULL,
  `low` FLOAT NULL,
  `high` FLOAT NULL,
  `open` FLOAT NULL,
  `close` FLOAT NULL,
  `volume` FLOAT NULL,
  PRIMARY KEY (`id`));
CREATE TABLE `infinitetrading`.`ETH-USD_6h` (
  `id` INT NOT NULL,
  `time` VARCHAR(225) NOT NULL,
  `low` FLOAT NULL,
  `high` FLOAT NULL,
  `open` FLOAT NULL,
  `close` FLOAT NULL,
  `volume` FLOAT NULL,
  PRIMARY KEY (`id`));
CREATE TABLE `infinitetrading`.`OP-USD_6h` (
  `id` INT NOT NULL,
  `time` VARCHAR(225) NOT NULL,
  `low` FLOAT NULL,
  `high` FLOAT NULL,
  `open` FLOAT NULL,
  `close` FLOAT NULL,
  `volume` FLOAT NULL,
  PRIMARY KEY (`id`));
CREATE TABLE `infinitetrading`.`MATIC-USD_1d` (
  `id` INT NOT NULL,
  `time` VARCHAR(225) NOT NULL,
  `low` FLOAT NULL,
  `high` FLOAT NULL,
  `open` FLOAT NULL,
  `close` FLOAT NULL,
  `volume` FLOAT NULL,
  PRIMARY KEY (`id`));
CREATE TABLE `infinitetrading`.`LINK-USD_6h` (
  `id` INT NOT NULL,
  `time` VARCHAR(225) NOT NULL,
  `low` FLOAT NULL,
  `high` FLOAT NULL,
  `open` FLOAT NULL,
  `close` FLOAT NULL,
  `volume` FLOAT NULL,
  PRIMARY KEY (`id`));

CREATE TABLE `infinitetrading`.`defi_accounts` (
  `account_id` INT NOT NULL,
  `platform_id` INT NULL,
  `network_id` INT NULL,
  `assets_id` FLOAT NULL,
  `allocations` VARCHAR(255) NULL,
  `trader_wallet_id` INT NULL,
  PRIMARY KEY (`account_id`));

CREATE TABLE `infinitetrading`.`networks_id` (
  `network_id` INT NOT NULL,
  `network_name` VARCHAR(255) NULL,
  `network_infura` VARCHAR(255) NULL,
  `network_gas_token` FLOAT NULL,
  PRIMARY KEY (`network_id`));

CREATE TABLE `infinitetrading`.`trader_wallets_id` (
  `wallet_id` INT NOT NULL,
  `private_key` VARCHAR(255) NULL,
  PRIMARY KEY (`wallet_id`));

