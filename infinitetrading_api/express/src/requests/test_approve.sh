#!/bin/bash
API_KEY="da586db798b805914362612017ceda607bbcb592915b60c118a06382535160b5cea57c19cc5af319ac33d2e41bf9d34522ffea91e68995e8ce0f35fd27ad24ea"
VAULT="0x4ce9628fae744c86b3e5435d6777aa4ff2cd15b6"
ASSET="0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"

curl -X POST "http://localhost:8005/approve?network=base&apiKey=$API_KEY&pool=$VAULT&platform=odos" \
  -H "Content-Type: application/json" \
  -d '{"asset":"'$ASSET'"}'

