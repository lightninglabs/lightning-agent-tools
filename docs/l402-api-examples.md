# Real-World L402 API Examples

These are live L402 APIs you can use with `lnget` to test Lightning payments. All endpoints return a `402 Payment Required` response with an embedded Lightning invoice — exactly how L402 is designed to work.

## Quick Start Examples

### Get Bitcoin fee estimates (50 sats)
```bash
lnget --max-cost 50 -X POST \
  -d '{"action":"l402_onchain_fee"}' \
  https://lightningfaucet.com/api/
```

### Get BTC price data (200 sats)
```bash
lnget --max-cost 200 -X POST \
  -d '{"action":"l402_price_oracle"}' \
  https://lightningfaucet.com/api/
```

### AI text completion via GPT-4o-mini (100 sats)
```bash
lnget --max-cost 100 -X POST \
  -d '{"action":"l402_llm_prompt","prompt":"Explain the Lightning Network in one sentence"}' \
  https://lightningfaucet.com/api/
```

### Get a Bitcoin fortune cookie (10 sats)
```bash
lnget --max-cost 10 -X POST \
  -d '{"action":"l402_fortune"}' \
  https://lightningfaucet.com/api/
```

### High-precision time + Bitcoin block height (10 sats)
```bash
lnget --max-cost 10 -X POST \
  -d '{"action":"l402_time"}' \
  https://lightningfaucet.com/api/
```

### Sentiment analysis (30 sats)
```bash
lnget --max-cost 30 -X POST \
  -d '{"action":"l402_sentiment","text":"Bitcoin is the future of money"}' \
  https://lightningfaucet.com/api/
```

## Multi-Provider Examples

The L402 ecosystem includes multiple providers. Here are examples from the [LightningFaucet L402 Registry](https://lightningfaucet.com/l402-registry):

### AI text generation via Maximum Sats (21 sats)
```bash
lnget --max-cost 21 -X POST \
  https://maximumsats.com/dvm
```

### Nostr Web of Trust score (1 sat)
```bash
lnget --max-cost 1 \
  "https://wot.klabo.world/score?pubkey=<hex_pubkey>"
```

### Bitcoin blockchain timestamping via CertVera (25,000 sats)
```bash
lnget --max-cost 25000 -X POST \
  -d '{"hash":"<sha256_hash>"}' \
  https://certvera.com/api/l402
```

## Discover More L402 APIs

Browse the full L402 API Registry at [lightningfaucet.com/l402-registry](https://lightningfaucet.com/l402-registry) — the only curated directory of L402-enabled APIs, with 4 providers, 36 endpoints across 5 categories.

API providers can submit new L402 endpoints for listing (1,000 sats listing fee, 24-hour review).
