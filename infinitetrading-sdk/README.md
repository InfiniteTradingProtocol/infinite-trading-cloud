# InfiniteTrading Sugar SDK

A simple SDK for fetching LP contract data on Optimism using Infura and ethers.js.

## Installation

```bash
npm install infinitetrading-sugar-sdk


mkdir infinitetrading-sugar
cd infinitetrading-sugar
npm init -y
npm install ethers axios dotenv
touch .env

INFURA_PROJECT_ID=your-infura-api-key
ABI_JSON='[{"constant":true,"inputs":[],"name":"exampleFunction","outputs":[{"name":"","type":"uint256"}],"type":"function"}]'

Replace your-infura-api-key and the ABI_JSON value with the actual values for your project.

touch sugar.ts

npm install --save-dev typescript
npx tsc --init

npx tsc sugar.ts
node build/sugar.js

npx tsc
