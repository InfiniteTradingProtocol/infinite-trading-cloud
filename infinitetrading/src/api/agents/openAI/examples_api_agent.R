curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"id":"lido-note","text":"stETH depeg risks include...", "metadata":{"source":"notes.md"}}'

  curl -X POST http://localhost:8000/advise \
  -H "Content-Type: application/json" \
  -d '{"q":"Summarize key stETH risks; include current ETH gas and price, plus top news."}'


