# BrownFi Sui

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
