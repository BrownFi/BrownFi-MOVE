# BrownFi MOVE
This repo is a MOVE codebase of BrownFi AMM intented to deploy on Sui blockchain.  
BrownFi has invented a novel oracle-based AMM with high capital efficiency and NO out-of-range. This thanks to a novel price mechanism which parameterizes legacy order-book model and is published in our research paper. BrownFi has high CE as Uniswap V3 and 200X higher than Uniswap V2. Additionally, BrownFi offers a simple UX (like Uniswap V2), suitable for both retail and professional LPs.  
BrownFi team consists of OGs and talents in blockchain and crypto space with 6+ years of experience. We developed and successfully launched multiple products: infra & tools, NFT marketplace, gaming launchpad, AMM and DeFi protocols. Via BrownFi AMM, we aim to unlock deep liquidity and high capital efficiency on SUI, a very new and emerging layer-1 ecosystem.
Try our demo here https://brownfi-sui.vercel.app/#/swap  

## cmd for tests

```bash
$ issue XBTC and USDT test coins
XBTC="0x9fb972059f12bcdded441399300076d7cff7d9946669d3a79b5fb837e2c49b09::coins::XBTC"
USDT="0x9fb972059f12bcdded441399300076d7cff7d9946669d3a79b5fb837e2c49b09::coins::USDT"
SUI="0x2::sui::SUI"

$ sui client publish --gas-budget 10000000
package=0xc6f8ce30d96bb9b728e000be94e25cab1a6011d1
global=0x28ae932ee07d4a0881e4bd24f630fe7b0d18a332

$ sui client objects

$ sui client call --gas-budget 10000000 \
  --package=$package \
  --module=interface \
  --function=add_liquidity \
  --args $global $sui_coin 1 $usdt_coin 1 \
  --type-args $SUI $USDT

# $ sui client split-coin --gas-budget 10000000 \
#   --coin-id $lp_sui_usdt \
#   --amounts 100000

$ sui client call --gas-budget 10000000 \
  --package=$package \
  --module=interface \
  --function=remove_liquidity \
  --args $global $lp_sui_usdt2 \
  --type-args $SUI $USDT

# sui -> usdt
$ sui client call --gas-budget 10000000 \
  --package=$package \
  --module=interface \
  --function=swap \
  --args $global $new_sui_coin 1  \
  --type-args $SUI $USDT

# usdt -> sui
sui client call --gas-budget 10000000 \
  --package=$package \
  --module=interface \
  --function=swap \
  --args $global $out_usdt_coin 1 \
  --type-args $USDT $SUI

$ sui client call --gas-budget 10000000 \
  --package=$package \
  --module=interface \
  --function=add_liquidity \
  --args $global $out_sui_coin 100 $new_usdt_coin 1000 \
  --type-args $SUI $USDT
```
