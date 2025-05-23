module brownfi_amm::swap;

use std::type_name::{Self, TypeName};
use sui::balance::{Self, Balance, Supply};
use sui::coin::{Self, Coin};
use sui::table::{Self, Table};
use sui::tx_context::sender;

use brownfi_amm::library;
use brownfi_amm::math;
use sui::event;

/// The input amount is zero.
const EZeroInput: u64 = 0;
/// Pool pair coin types must be ordered alphabetically (`A` < `B`) and mustn't be equal.
const EInvalidPair: u64 = 1;
/// Pool for this pair already exists.
const EPoolAlreadyExists: u64 = 2;
/// The pool balance differs from the acceptable.
const EExcessiveSlippage: u64 = 3;
/// There's no liquidity in the pool.
const ENoLiquidity: u64 = 4;

const LP_FEE_BASE: u64 = 10_000;

/*=== Events === */
public struct PoolCreated has copy, drop {
    pool_id: ID,
    a: TypeName,
    b: TypeName,
    init_a: u64,
    init_b: u64,
    lp_minted: u64,
}

public struct AddLiquidity has copy, drop {
    pool_id: ID,
    a: TypeName,
    b: TypeName,
    amount_in_a: u64,
    amount_in_b: u64,
    lp_minted: u64,
}

public struct RemoveLiquidity has copy, drop {
    pool_id: ID,
    a: TypeName,
    b: TypeName,
    amount_out_a: u64,
    amount_out_b: u64,
    lp_burnt: u64,
}

public struct Swap has copy, drop {
    pool_id: ID,
    token_in: TypeName,
    amount_in: u64,
    token_out: TypeName,
    amount_out: u64,
}

/* === LP witness === */
public struct LP<phantom A, phantom B> has drop {}

/* === Pool === */
public struct Pool<phantom A, phantom B> has key {
    id: UID,
    balance_a: Balance<A>,
    balance_b: Balance<B>,
    lp_supply: Supply<LP<A, B>>,
    fee_points: u64,
}

public fun pool_balances<A, B>(pool: &Pool<A, B>): (u64, u64, u64) {
    (
        balance::value(&pool.balance_a),
        balance::value(&pool.balance_b),
        balance::supply_value(&pool.lp_supply)
    )
}

public fun pool_fees<A, B>(pool: &Pool<A, B>): u64 {
    pool.fee_points
}

/* === Factory === */
public struct Factory has key {
    id: UID,
    table: Table<PoolItem, bool>,
}

public struct PoolItem has copy, drop, store  {
    a: TypeName,
    b: TypeName
}

fun add_pool<A, B>(factory: &mut Factory) {
    let a = type_name::get<A>();
    let b = type_name::get<B>();
    assert!(library::sort_names(&a, &b) == 0, EInvalidPair);

    let item = PoolItem{ a, b };
    assert!(table::contains(&factory.table, item) == false, EPoolAlreadyExists);

    table::add(&mut factory.table, item, true)
}

    /* === main logic === */

fun init(ctx: &mut TxContext) {
    let factory = Factory { 
        id: object::new(ctx),
        table: table::new(ctx),
    };
    transfer::share_object(factory);
}

public fun create_pool<A, B>(factory: &mut Factory, init_a: Balance<A>, init_b: Balance<B>, ctx: &mut TxContext): Balance<LP<A, B>> {
    assert!(balance::value(&init_a) > 0 && balance::value(&init_b) > 0, EZeroInput);

    add_pool<A, B>(factory);

    // create pool
    let mut pool = Pool<A, B> {
        id: object::new(ctx),
        balance_a: init_a,
        balance_b: init_b,
        lp_supply: balance::create_supply(LP<A, B> {}),
        fee_points: 30, // 0.3%
    };

    // mint initial lp tokens
    let lp_amount = math::mul_sqrt(balance::value(&pool.balance_a), balance::value(&pool.balance_b));
    let lp_balance = balance::increase_supply(&mut pool.lp_supply, lp_amount);

    event::emit(PoolCreated {
        pool_id: object::id(&pool),
        a: type_name::get<A>(),
        b: type_name::get<B>(),
        init_a: balance::value(&pool.balance_a),
        init_b: balance::value(&pool.balance_b),
        lp_minted: lp_amount
    });

    transfer::share_object(pool);

    lp_balance
}

public fun add_liquidity<A, B>(pool: &mut Pool<A, B>, mut input_a: Balance<A>, mut input_b: Balance<B>, min_lp_out: u64): (Balance<A>, Balance<B>, Balance<LP<A, B>>) {
    assert!(balance::value(&input_a) > 0 && balance::value(&input_b) > 0, EZeroInput);

    // calculate the deposit amounts
    let input_a_mul_pool_b: u128 = (balance::value(&input_a) as u128) * (balance::value(&pool.balance_b) as u128);
    let input_b_mul_pool_a: u128 = (balance::value(&input_b) as u128) * (balance::value(&pool.balance_a) as u128);

    let deposit_a: u64;
    let deposit_b: u64;
    let lp_to_issue: u64;
    if (input_a_mul_pool_b > input_b_mul_pool_a) { // input_a / pool_a > input_b / pool_b
        deposit_b = balance::value(&input_b);
        // pool_a * deposit_b / pool_b
        deposit_a = (math::ceil_div_u128(
            input_b_mul_pool_a,
            (balance::value(&pool.balance_b) as u128),
        ) as u64);
        // deposit_b / pool_b * lp_supply
        lp_to_issue = math::mul_div(
            deposit_b,
            balance::supply_value(&pool.lp_supply),
            balance::value(&pool.balance_b)
        );
    } else if (input_a_mul_pool_b < input_b_mul_pool_a) { // input_a / pool_a < input_b / pool_b
        deposit_a = balance::value(&input_a);
        // pool_b * deposit_a / pool_a
        deposit_b = (math::ceil_div_u128(
            input_a_mul_pool_b,
            (balance::value(&pool.balance_a) as u128),
        ) as u64);
        // deposit_a / pool_a * lp_supply
        lp_to_issue = math::mul_div(
            deposit_a,
            balance::supply_value(&pool.lp_supply),
            balance::value(&pool.balance_a)
        );
    } else {
        deposit_a = balance::value(&input_a);
        deposit_b = balance::value(&input_b);
        if (balance::supply_value(&pool.lp_supply) == 0) {
            // in this case both pool balances are 0 and lp supply is 0
            lp_to_issue = math::mul_sqrt(deposit_a, deposit_b);
        } else {
            // the ratio of input a and b matches the ratio of pool balances
            lp_to_issue = math::mul_div(
                deposit_a,
                balance::supply_value(&pool.lp_supply),
                balance::value(&pool.balance_a)
            );
        }
    };

    // deposit amounts into pool 
    balance::join(
        &mut pool.balance_a,
        balance::split(&mut input_a, deposit_a)
    );
    balance::join(
        &mut pool.balance_b,
        balance::split(&mut input_b, deposit_b)
    );

    // mint lp coin
    assert!(lp_to_issue >= min_lp_out, EExcessiveSlippage);
    let lp = balance::increase_supply(&mut pool.lp_supply, lp_to_issue);

    event::emit(AddLiquidity {
        pool_id: object::id(pool),
        a: type_name::get<A>(),
        b: type_name::get<B>(),
        amount_in_a: deposit_a,
        amount_in_b: deposit_b,
        lp_minted: lp_to_issue,
    });

    // return
    (input_a, input_b, lp)
}

public fun remove_liquidity<A, B>(pool: &mut Pool<A, B>, lp_in: Balance<LP<A, B>>, min_a_out: u64, min_b_out: u64): (Balance<A>, Balance<B>) {
    assert!(balance::value(&lp_in) > 0, EZeroInput);

    // calculate output amounts
    let lp_in_amount = balance::value(&lp_in);
    let pool_a_amount = balance::value(&pool.balance_a);
    let pool_b_amount = balance::value(&pool.balance_b);
    let lp_supply = balance::supply_value(&pool.lp_supply);

    let a_out = math::mul_div(lp_in_amount, pool_a_amount, lp_supply);
    let b_out = math::mul_div(lp_in_amount, pool_b_amount, lp_supply);
    assert!(a_out >= min_a_out, EExcessiveSlippage);
    assert!(b_out >= min_b_out, EExcessiveSlippage);

    // burn lp tokens
    balance::decrease_supply(&mut pool.lp_supply, lp_in);

    event::emit(RemoveLiquidity {
        pool_id: object::id(pool),
        a: type_name::get<A>(),
        b: type_name::get<B>(),
        amount_out_a: a_out,
        amount_out_b: b_out,
        lp_burnt: lp_in_amount,
    });

    // return amounts
    (
        balance::split(&mut pool.balance_a, a_out),
        balance::split(&mut pool.balance_b, b_out)
    )
}

public fun swap_a_for_b<A, B>(pool: &mut Pool<A, B>, input: Balance<A>, min_out: u64): Balance<B> {
    assert!(balance::value(&input) > 0, EZeroInput);
    assert!(balance::value(&pool.balance_a) > 0 && balance::value(&pool.balance_b) > 0, ENoLiquidity);

    // calculate swap result
    let input_amount = balance::value(&input);
    let pool_a_amount = balance::value(&pool.balance_a);
    let pool_b_amount = balance::value(&pool.balance_b);

    let out_amount = calc_swap_out(input_amount, pool_a_amount, pool_b_amount, pool.fee_points);

    assert!(out_amount >= min_out, EExcessiveSlippage);

    // deposit input
    balance::join(&mut pool.balance_a, input);

    event::emit(Swap {
        pool_id: object::id(pool),
        token_in: type_name::get<A>(),
        amount_in: input_amount,
        token_out: type_name::get<B>(),
        amount_out: out_amount,
    });

    // return output
    balance::split(&mut pool.balance_b, out_amount)
}

public fun swap_b_for_a<A, B>(pool: &mut Pool<A, B>, input: Balance<B>, min_out: u64): Balance<A> {
    assert!(balance::value(&input) > 0, EZeroInput);
    assert!(balance::value(&pool.balance_a) > 0 && balance::value(&pool.balance_b) > 0, ENoLiquidity);

    // calculate swap result
    let input_amount = balance::value(&input);
    let pool_b_amount = balance::value(&pool.balance_b);
    let pool_a_amount = balance::value(&pool.balance_a);

    let out_amount = calc_swap_out(input_amount, pool_b_amount, pool_a_amount, pool.fee_points);

    assert!(out_amount >= min_out, EExcessiveSlippage);

    // deposit input
    balance::join(&mut pool.balance_b, input);

    event::emit(Swap {
        pool_id: object::id(pool),
        token_in: type_name::get<B>(),
        amount_in: input_amount,
        token_out: type_name::get<A>(),
        amount_out: out_amount,
    });

    // return output
    balance::split(&mut pool.balance_a, out_amount)
}

/// Calclates swap result and fees based on the input amount and current pool state.
fun calc_swap_out(input_amount: u64, input_pool_amount: u64, out_pool_amount: u64, fee_points: u64): u64 {
    // calc out value
    let fee_amount = math::ceil_mul_div(input_amount, fee_points, LP_FEE_BASE);
    let input_amount_after_fee = input_amount - fee_amount;
    // (out_pool_amount - out_amount) * (input_pool_amount + input_amount_after_fee) = out_pool_amount * input_pool_amount
    // (out_pool_amount - out_amount) / out_pool_amount = input_pool_amount / (input_pool_amount + input_amount_after_fee)
    // out_amount / out_pool_amount = input_amount_after_fee / (input_pool_amount + input_amount_after_fee)
    let out_amount = math::mul_div(input_amount_after_fee, out_pool_amount, input_pool_amount + input_amount_after_fee);

    out_amount
}

/* === with coin === */

fun destroy_zero_or_transfer_balance<T>(balance: Balance<T>, recipient: address, ctx: &mut TxContext) {
    if (balance::value(&balance) == 0) {
        balance::destroy_zero(balance);
    } else {
        transfer::public_transfer(coin::from_balance(balance, ctx), recipient);
    };
}

public fun create_pool_with_coins<A, B>(factory: &mut Factory, init_a: Coin<A>, init_b: Coin<B>, ctx: &mut TxContext): Coin<LP<A, B>> {
    let lp_balance = create_pool(factory, coin::into_balance(init_a), coin::into_balance(init_b), ctx);
    
    coin::from_balance(lp_balance, ctx)
}

public entry fun create_pool_with_coins_and_transfer_lp_to_sender<A, B>(factory: &mut Factory, init_a: Coin<A>, init_b: Coin<B>, ctx: &mut TxContext) {
    let lp_balance = create_pool(factory, coin::into_balance(init_a), coin::into_balance(init_b), ctx);
    transfer::public_transfer(coin::from_balance(lp_balance, ctx), sender(ctx));
}

public fun add_liquidity_with_coins<A, B>(pool: &mut Pool<A, B>, input_a: Coin<A>, input_b: Coin<B>, min_lp_out: u64, ctx: &mut TxContext): (Coin<A>, Coin<B>, Coin<LP<A, B>>) {
    let (remaining_a, remaining_b, lp) = add_liquidity(pool, coin::into_balance(input_a), coin::into_balance(input_b), min_lp_out);

    (
        coin::from_balance(remaining_a, ctx),
        coin::from_balance(remaining_b, ctx),
        coin::from_balance(lp, ctx),
    )
}

public entry fun add_liquidity_with_coins_and_transfer_to_sender<A, B>(pool: &mut Pool<A, B>, input_a: Coin<A>, input_b: Coin<B>, min_lp_out: u64, ctx: &mut TxContext) {
    let (remaining_a, remaining_b, lp) = add_liquidity(pool, coin::into_balance(input_a), coin::into_balance(input_b), min_lp_out);
    let sender = sender(ctx);
    destroy_zero_or_transfer_balance(remaining_a, sender, ctx);
    destroy_zero_or_transfer_balance(remaining_b, sender, ctx);
    destroy_zero_or_transfer_balance(lp, sender, ctx);
}

public fun remove_liquidity_with_coins<A, B>(pool: &mut Pool<A, B>, lp_in: Coin<LP<A, B>>, min_a_out: u64, min_b_out: u64, ctx: &mut TxContext): (Coin<A>, Coin<B>) {
    let (a_out, b_out) = remove_liquidity(pool, coin::into_balance(lp_in), min_a_out, min_b_out);

    (
        coin::from_balance(a_out, ctx),
        coin::from_balance(b_out, ctx),
    )
}

public entry fun remove_liquidity_with_coins_and_transfer_to_sender<A, B>(pool: &mut Pool<A, B>, lp_in: Coin<LP<A, B>>, min_a_out: u64, min_b_out: u64, ctx: &mut TxContext) {
    let (a_out, b_out) = remove_liquidity(pool, coin::into_balance(lp_in), min_a_out, min_b_out);
    let sender = sender(ctx);
    destroy_zero_or_transfer_balance(a_out, sender, ctx);
    destroy_zero_or_transfer_balance(b_out, sender, ctx);
}

public fun swap_a_for_b_with_coin<A, B>(pool: &mut Pool<A, B>, input: Coin<A>, min_out: u64, ctx: &mut TxContext): Coin<B> {
    let b_out = swap_a_for_b(pool, coin::into_balance(input), min_out);

    coin::from_balance(b_out, ctx)
}

public entry fun swap_a_for_b_with_coin_and_transfer_to_sender<A, B>(pool: &mut Pool<A, B>, input: Coin<A>, min_out: u64, ctx: &mut TxContext) {
    let b_out = swap_a_for_b(pool, coin::into_balance(input), min_out);
    transfer::public_transfer(coin::from_balance(b_out, ctx), sender(ctx));
}

public fun swap_b_for_a_with_coin<A, B>(pool: &mut Pool<A, B>, input: Coin<B>, min_out: u64, ctx: &mut TxContext): Coin<A> {
    let a_out = swap_b_for_a(pool, coin::into_balance(input), min_out);

    coin::from_balance(a_out, ctx)
}

public entry fun swap_b_for_a_with_coin_and_transfer_to_sender<A, B>(pool: &mut Pool<A, B>, input: Coin<B>, min_out: u64, ctx: &mut TxContext) {
    let a_out = swap_b_for_a(pool, coin::into_balance(input), min_out);
    transfer::public_transfer(coin::from_balance(a_out, ctx), sender(ctx));
}

/* === test === */

#[test_only]
public fun test_init(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public struct BAR has drop {}
#[test_only]
public struct FOO has drop {}
#[test_only]
public struct FOOD has drop {}
#[test_only]
public struct FOOd has drop {}

#[test]
fun test_cmp_type_names() {
    assert!(library::sort_names(&type_name::get<BAR>(), &type_name::get<FOO>()) == 0, 0);
    assert!(library::sort_names(&type_name::get<FOO>(), &type_name::get<FOO>()) == 1, 0);
    assert!(library::sort_names(&type_name::get<FOO>(), &type_name::get<BAR>()) == 2, 0);

    assert!(library::sort_names(&type_name::get<FOO>(), &type_name::get<FOOd>()) == 0, 0);
    assert!(library::sort_names(&type_name::get<FOOd>(), &type_name::get<FOO>()) == 2, 0);

    assert!(library::sort_names(&type_name::get<FOOD>(), &type_name::get<FOOd>()) == 0, 0);
    assert!(library::sort_names(&type_name::get<FOOd>(), &type_name::get<FOOD>()) == 2, 0);
}

#[test_only]
fun test_destroy_empty_factory(factory: Factory) {
    let Factory { id, table } = factory;
    object::delete(id);
    table::destroy_empty(table);
}

#[test_only]
fun test_remove_pool_item<A, B>(factory: &mut Factory) {
    let a = type_name::get<A>();
    let b = type_name::get<B>();
    table::remove(&mut factory.table, PoolItem{ a, b });
}

#[test]
fun test_factory() {
    let ctx = &mut tx_context::dummy();
    let mut factory = Factory { 
        id: object::new(ctx),
        table: table::new(ctx),
    };

    add_pool<BAR, FOO>(&mut factory);
    add_pool<FOO, FOOd>(&mut factory);

    test_remove_pool_item<BAR, FOO>(&mut factory);
    test_remove_pool_item<FOO, FOOd>(&mut factory);
    test_destroy_empty_factory(factory);
}

#[test]
#[expected_failure(abort_code = EInvalidPair)]
fun test_add_pool_aborts_on_wrong_order() {
    let ctx = &mut tx_context::dummy();
    let mut factory = Factory { 
        id: object::new(ctx),
        table: table::new(ctx),
    };

    add_pool<FOO, BAR>(&mut factory);

    test_remove_pool_item<FOO, BAR>(&mut factory);
    test_destroy_empty_factory(factory);
}

#[test]
#[expected_failure(abort_code = EInvalidPair)]
fun test_add_pool_aborts_on_same_type() {
    let ctx = &mut tx_context::dummy();
    let mut factory = Factory { 
        id: object::new(ctx),
        table: table::new(ctx),
    };

    add_pool<FOO, FOO>(&mut factory);

    test_remove_pool_item<FOO, FOO>(&mut factory);
    test_destroy_empty_factory(factory);
}

#[test]
#[expected_failure(abort_code = EPoolAlreadyExists)]
fun test_add_pool_aborts_on_already_exists() {
    let ctx = &mut tx_context::dummy();
    let mut factory = Factory { 
        id: object::new(ctx),
        table: table::new(ctx),
    };

    add_pool<BAR, FOO>(&mut factory);
    add_pool<BAR, FOO>(&mut factory); // aborts here

    test_remove_pool_item<BAR, FOO>(&mut factory);
    test_destroy_empty_factory(factory);
}
