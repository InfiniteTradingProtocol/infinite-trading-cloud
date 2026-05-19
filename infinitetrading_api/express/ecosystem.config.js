module.exports = {
  apps: [
    {
      name: 'infinitetrading-api',
      script: './express/build/src/index.js',
      cwd: '/home/ubuntu/infinitetrading/src',
      instances: 1,
      exec_mode: 'fork',
      watch: false,
      max_memory_restart: '500M',
      env: {
        NODE_ENV: 'production',
        PORT: 8000
      },
      error_file: 'express/logs/pm2-error.log',
      out_file: 'express/logs/pm2-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      // PM2 log rotation
      log_type: 'json',
      max_size: '50M',
      retain: 10,
      compress: true,
      // Auto-restart on crash
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      // Graceful shutdown
      kill_timeout: 5000,
      listen_timeout: 3000
    },
    {
      name: 'api-gateway',
      script: 'Rscript',
      args: 'plumber/gateway/gateway.R',
      cwd: '/home/ubuntu/infinitetrading/src',
      instances: 1,
      exec_mode: 'fork',
      watch: false,
      max_memory_restart: '1G',
      env: {
        PORT: 8003
      },
      error_file: 'plumber/logs/gateway-error.log',
      out_file: 'plumber/logs/gateway-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      // PM2 log rotation
      max_size: '50M',
      retain: 10,
      compress: true,
      // Auto-restart on crash
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      // Graceful shutdown
      kill_timeout: 5000,
      listen_timeout: 3000
    },
    {
      name: 'plumber-api',
      script: 'Rscript',
      args: 'plumber/api.R',
      cwd: '/home/ubuntu/infinitetrading/src',
      instances: 1,
      exec_mode: 'fork',
      watch: false,
      max_memory_restart: '1G',
      env: {
        PORT: 8002
      },
      error_file: 'plumber/logs/plumber-error.log',
      out_file: 'plumber/logs/plumber-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      // PM2 log rotation
      max_size: '50M',
      retain: 10,
      compress: true,
      // Auto-restart on crash
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      // Graceful shutdown
      kill_timeout: 5000,
      listen_timeout: 3000
    },
    {
      name: 'candles-collector',
      script: 'python3',
      args: 'db/candles.py',
      cwd: '/home/ubuntu/infinitetrading/src',
      instances: 1,
      exec_mode: 'fork',
      watch: false,
      max_memory_restart: '200M',
      error_file: 'logs/candles-error.log',
      out_file: 'logs/candles-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      // PM2 log rotation
      max_size: '50M',
      retain: 10,
      compress: true,
      // Auto-restart on crash
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      // Graceful shutdown
      kill_timeout: 5000
    },
    {
      name: 'messages-collector',
      script: 'python3',
      args: 'data-collectors/db/messages.py',
      cwd: '/home/ubuntu/infinitetrading/src',
      instances: 1,
      exec_mode: 'fork',
      watch: false,
      max_memory_restart: '200M',
      error_file: 'data-collectors/logs/messages-error.log',
      out_file: 'data-collectors/logs/messages-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      // PM2 log rotation
      max_size: '50M',
      retain: 10,
      compress: true,
      // Auto-restart on crash
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      // Graceful shutdown
      kill_timeout: 5000
    },
    {
      name: 'ml-models',
      script: 'Rscript',
      args: 'models.R',
      cwd: '/home/ubuntu/infinitetrading/src',
      instances: 1,
      exec_mode: 'fork',
      watch: false,
      max_memory_restart: '500M',
      error_file: 'logs/ml-models-error.log',
      out_file: 'logs/ml-models-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      // PM2 log rotation
      max_size: '50M',
      retain: 10,
      compress: true,
      // Auto-restart on crash
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      // Graceful shutdown
      kill_timeout: 5000
    },
    // ========================================
    // ETH Yield Vault (Base) – 15-min Fluid/AAVE optimizer
    // Vault: 0x54db076bfac96c02e9a2a66410d69f35ac481fe6
    // ========================================
    {
      name: 'strategy-eth-yield-vault',
      script: 'Rscript',
      args: 'strategies/eth_yield_vault.R',
      cwd: '/home/ubuntu/infinitetrading/src',
      instances: 1,
      exec_mode: 'fork',
      watch: false,
      max_memory_restart: '1G',
      env: {
        DISABLE_DB_POOL: 'true'
      },
      error_file: 'logs/strategy-eth-yield-vault-error.log',
      out_file: 'logs/strategy-eth-yield-vault-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      max_size: '50M',
      retain: 10,
      compress: true,
      autorestart: true,
      max_restarts: 100,
      min_uptime: '30s',
      kill_timeout: 5000
    }
  ]
};