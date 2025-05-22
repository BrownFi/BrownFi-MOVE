module brownfi_amm::library;

use std::type_name::{Self, TypeName};
use std::ascii;

// compare two type names
public fun sort_names(a: &TypeName, b: &TypeName): u8 {
    let bytes_a = ascii::as_bytes(type_name::borrow_string(a));
    let bytes_b = ascii::as_bytes(type_name::borrow_string(b));

    let len_a = vector::length(bytes_a);
    let len_b = vector::length(bytes_b);

    let mut i = 0;
    let n = std::u64::min(len_a, len_b);
    while (i < n) {
        let a = *vector::borrow(bytes_a, i);
        let b = *vector::borrow(bytes_b, i);

        if (a < b) {
            return 0
        };
        if (a > b) {
            return 2
        };
        i = i + 1;
    };

    if (len_a == len_b) {
        1
    } else if (len_a < len_b) {
        0
    } else {
        2
    }
}

