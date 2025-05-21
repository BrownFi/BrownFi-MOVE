// Copyright 2022 OmniBTC Authors. Licensed under Apache-2.0 License.
module brownfi_amm::math {

    /// Calculates (a * b) / c. Errors if result doesn't fit into u64.
    public fun mul_div(a: u64, b: u64, c: u64): u64 {
        ((((a as u128) * (b as u128)) / (c as u128)) as u64)
    }

    /// Calculates ceil_div((a * b), c). Errors if result doesn't fit into u64.
    public fun ceil_mul_div(a: u64, b: u64, c: u64): u64 {
        (ceil_div_u128((a as u128) * (b as u128), (c as u128)) as u64)
    }

    /// Calculates sqrt(a * b).
    public fun mul_sqrt(a: u64, b: u64): u64 {
        (std::u128::sqrt((a as u128) * (b as u128)) as u64)
    }

    /// Calculates ceil(a / b).
    public fun ceil_div_u128(a: u128, b: u128): u128 {
        if (a == 0) 0 else (a - 1) / b + 1
    }
}
