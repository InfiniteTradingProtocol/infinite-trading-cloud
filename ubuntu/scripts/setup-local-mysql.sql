-- Setup script for local MySQL database
-- Run this on EC2 to create tables for predictions and messages

CREATE DATABASE IF NOT EXISTS infinitetrading;
USE infinitetrading;

-- Messages table (for Discord/Slack notifications)
CREATE TABLE IF NOT EXISTS messages (
  timestamp DATETIME(6) NOT NULL,
  platform VARCHAR(50) NOT NULL,
  channel VARCHAR(255) NOT NULL,
  message VARCHAR(255) NOT NULL,
  PRIMARY KEY (timestamp, platform, message),
  INDEX idx_platform_timestamp (platform, timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Predictions table (for ML model outputs)
CREATE TABLE IF NOT EXISTS predictions (
  symbol VARCHAR(50) NOT NULL,
  model_name VARCHAR(100) NOT NULL DEFAULT 'default',
  prediction DECIMAL(10, 6) NOT NULL,
  stoploss DECIMAL(10, 6) NULL,
  timestamp DATETIME NOT NULL,
  PRIMARY KEY (symbol, model_name),
  INDEX idx_timestamp (timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Clean up old predictions (older than 24 hours)
-- This can be run as a cron job
-- DELETE FROM predictions WHERE timestamp < DATE_SUB(NOW(), INTERVAL 24 HOUR);

-- Clean up old messages (older than 7 days)
-- DELETE FROM messages WHERE timestamp < DATE_SUB(NOW(), INTERVAL 7 DAY);

-- Grant permissions
-- Run this after creating the user in MySQL:
-- CREATE USER IF NOT EXISTS 'richard_clare'@'localhost' IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON infinitetrading.* TO 'richard_clare'@'localhost';
FLUSH PRIVILEGES;

-- Verify tables
SHOW TABLES;
DESCRIBE messages;
DESCRIBE predictions;

SELECT 'Local MySQL setup complete!' as status;
