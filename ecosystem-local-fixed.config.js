module.exports = {
  apps: [
    // API Services
    {
      name: 'express-api',
      script: './express/build/src/index.js',
      cwd: '/Users/richardclare/infinite-trading-api',
      env: { NODE_ENV: 'development', PORT: 8000 },
      error_file: 'express/logs/pm2-error.log',
      out_file: 'express/logs/pm2-out.log',
      autorestart: true
    },
    {
      name: 'plumber-api',
      script: 'Rscript',
      args: 'plumber/api.R',
      cwd: '/Users/richardclare/infinite-trading-api',
      env: { PORT: 8002, wd: '/Users/richardclare/infinite-trading-api/' },
      error_file: 'plumber/logs/plumber-error.log',
      out_file: 'plumber/logs/plumber-out.log',
      autorestart: true
    },
    {
      name: 'gateway',
      script: 'Rscript',
      args: 'plumber/gateway/gateway.R',
      cwd: '/Users/richardclare/infinite-trading-api',
      env: { PORT: 8003, wd: '/Users/richardclare/infinite-trading-api/' },
      error_file: 'plumber/logs/gateway-error.log',
      out_file: 'plumber/logs/gateway-out.log',
      autorestart: true
    },
    
    // Data Collectors 
    {
      name: 'collector-candles',
      script: 'python3',
      args: 'data-collectors/db/candles.py',
      cwd: '/Users/richardclare/infinite-trading-api',
      error_file: 'data-collectors/logs/candles-error.log',
      out_file: 'data-collectors/logs/candles-out.log',
      autorestart: true
    },
    {
      name: 'collector-messages',
      script: 'python3',
      args: 'data-collectors/db/messages.py',
      cwd: '/Users/richardclare/infinite-trading-api',
      error_file: 'data-collectors/logs/messages-error.log',
      out_file: 'data-collectors/logs/messages-out.log',
      autorestart: true
    }
  ]
};
