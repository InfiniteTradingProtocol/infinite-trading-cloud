// Load environment variables from .env file
const fs = require('fs');
const envPath = '/home/ubuntu/infinitetrading_api/.env';
if (fs.existsSync(envPath)) {
  const envContent = fs.readFileSync(envPath, 'utf8');
  envContent.split('\n').forEach(line => {
    const match = line.match(/^([^#=]+)=(.*)$/);
    if (match) {
      const key = match[1].trim();
      const value = match[2].trim().replace(/^["']|["']$/g, '');
      process.env[key] = value;
    }
  });
}

module.exports = {
  apps: [
    // ========================================
    // API Services
    // ========================================
    {
      name: "infinitetrading-api",
      script: "./build/src/index.js",
      cwd: "/home/ubuntu/infinitetrading_api/express",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "500M",
      env: {
        NODE_ENV: "production",
        PORT: 8000
      },
      error_file: "logs/pm2-error.log",
      out_file: "logs/pm2-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      log_type: "json",
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      kill_timeout: 5000,
      listen_timeout: 3000
    },
    {
      name: "api-gateway",
      script: "Rscript",
      args: "api/gateway/gateway.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "1G",
      env: {
        PORT: 8003,
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/gateway-error.log",
      out_file: "logs/gateway-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      kill_timeout: 5000,
      listen_timeout: 3000
    },
    {
      name: "plumber-api",
      script: "Rscript",
      args: "api/api.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "1G",
      env: {
        PORT: 8002,
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/plumber-error.log",
      out_file: "logs/plumber-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      kill_timeout: 5000,
      listen_timeout: 3000
    },
    // ========================================
    // Data Collectors
    // ========================================
    {
      name: "candles-collector",
      script: "python3",
      args: "db/candles.py",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "200M",
      env: {
        DB_HOST: "127.0.0.1",
        DB_PORT: "3306",
        DB_USER: process.env.db_user_local,
        DB_PASSWORD: process.env.db_password_local,
        DB_NAME: "infinitetrading"
      },
      error_file: "logs/candles-error.log",
      out_file: "logs/candles-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      kill_timeout: 5000
    },
    {
      name: "messages-collector",
      script: "python3",
      args: "db/messages.py",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "200M",
      env: {
        db_user_local: process.env.db_user_local,
        db_password_local: process.env.db_password_local
      },
      error_file: "logs/messages-error.log",
      out_file: "logs/messages-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      kill_timeout: 5000
    },
    // ========================================
    // ML Models
    // ========================================
    {
      name: "ml-models",
      script: "Rscript",
      args: "models.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "2G",
      env: {
        DISABLE_DB_POOL: "true",
        db_user_local: process.env.db_user_local,
        db_password_local: process.env.db_password_local
      },
      error_file: "logs/ml-models-error.log",
      out_file: "logs/ml-models-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 1000,
      min_uptime: "5s",
      kill_timeout: 10000
    },
    // ========================================
    // Trading Bot & Monitoring
    // ========================================
    {
      name: "tradebot",
      script: "Rscript",
      args: "api/trading.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "1G",
      env: {
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/tradebot-error.log",
      out_file: "logs/tradebot-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 100,
      min_uptime: "30s",
      kill_timeout: 10000
    },
    {
      name: "gas-monitor",
      script: "Rscript",
      args: "api/gasMonitor.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "1G",
      env: {
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/gas-monitor-error.log",
      out_file: "logs/gas-monitor-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 100,
      min_uptime: "30s",
      kill_timeout: 5000
    },
    {
      name: "pools-monitor",
      script: "Rscript",
      args: "tradebot/pools.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "1G",
      env: {
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/pools-error.log",
      out_file: "logs/pools-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 100,
      min_uptime: "30s",
      kill_timeout: 5000
    },
    {
      name: "prices-monitor",
      script: "Rscript",
      args: "prices.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "500M",
      env: {
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/prices-error.log",
      out_file: "logs/prices-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 100,
      min_uptime: "30s",
      kill_timeout: 5000
    },
    {
      name: "yields-monitor",
      script: "Rscript",
      args: "api/yields.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "1G",
      env: {
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/yields-error.log",
      out_file: "logs/yields-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 100,
      min_uptime: "30s",
      kill_timeout: 5000
    },
    // ========================================
    // Trading Strategies
    // ========================================
    {
      name: "strategy-aero-ema-crossover",
      script: "Rscript",
      args: "strategies/aero_ema_11_33_crossover.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "1G",
      env: {
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/strategy-aero-ema-error.log",
      out_file: "logs/strategy-aero-ema-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 100,
      min_uptime: "30s",
      kill_timeout: 5000
    },
    {
      name: "strategy-velo1d-bot",
      script: "Rscript",
      args: "strategies/Velo1DBot.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "1G",
      env: {
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/strategy-velo1d-error.log",
      out_file: "logs/strategy-velo1d-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 100,
      min_uptime: "30s",
      kill_timeout: 5000
    },
    {
      name: "strategy-supertrend",
      script: "Rscript",
      args: "strategies/superTrend.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "1G",
      env: {
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/strategy-supertrend-error.log",
      out_file: "logs/strategy-supertrend-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 100,
      min_uptime: "30s",
      kill_timeout: 5000
    },
    {
      name: "strategy-op-probability",
      script: "Rscript",
      args: "strategies/OP_probability_model.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "1G",
      env: {
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/strategy-op-error.log",
      out_file: "logs/strategy-op-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 100,
      min_uptime: "30s",
      kill_timeout: 5000
    },
    {
      name: "strategy-crossovers",
      script: "Rscript",
      args: "strategies/crossOvers.R",
      cwd: "/home/ubuntu/infinitetrading/src",
      instances: 1,
      exec_mode: "fork",
      watch: false,
      max_memory_restart: "1G",
      env: {
        DISABLE_DB_POOL: "true"
      },
      error_file: "logs/strategy-crossovers-error.log",
      out_file: "logs/strategy-crossovers-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      max_size: "50M",
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 100,
      min_uptime: "30s",
      kill_timeout: 5000
    }
  ]
};
