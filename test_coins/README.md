# Test coins

## cmd

```bash
# deploy on sui devnet 0.18
sui client publish --gas-budget 100000000
package=0x58188d537f33ac825e7199a2fc5c6d22558ffd89a2320be292591026a8efc03a
faucet=0xd4575fae90c78ad3b781f4d686bab3c16b089f03e2b4f5c932b18fda481a335d
USDT="$package::coins::USDT"
XBTC="$package::coins::XBTC"

# require deployed swap
swap_global=0x9fb972059f12bcdded441399300076d7cff7d9946669d3a79b5fb837e2c49b09

# add faucet admin
sui client call \
  --gas-budget 100000000 \
  --package $package \
  --module faucet \
  --function add_admin \
  --args $faucet \
      0xd4575fae90c78ad3b781f4d686bab3c16b089f03e2b4f5c932b18fda481a335d

# claim usdt
sui client call \
  --gas-budget 100000000 \
  --package $package \
  --module faucet \
  --function claim \
  --args $faucet \
  --type-args $USDT

# force claim xbtc with amount
# 10 means 10*ONE_COIN
sui client call \
  --gas-budget 100000000 \
  --package $package \
  --module faucet \
  --function force_claim \
  --args $faucet 10 \
  --type-args $XBTC

# add new coin supply
PCX_CAP=0xfe6db5a5802acb32b566d7b7d1fbdf55a496eb7f
PCX="0x44984b1d38594dc64a380391359b46ae4207d165::pcx::PCX"
sui client call \
  --gas-budget 100000000 \
  --package $package \
  --module faucet \
  --function add_supply \
  --args $faucet \
         $PCX_CAP \
  --type-args $PCX

# force add liquidity
sui client call \
  --gas-budget 100000000 \
  --package $package \
  --module faucet \
  --function force_add_liquidity \
  --args $faucet $swap_global
```
