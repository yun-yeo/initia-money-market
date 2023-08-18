module my_addr::MoneyMarket {
    use std::block;
    use std::coin::{Self, Coin};
    use std::decimal256::{Self, Decimal256};
    use std::error;
    use std::signer;
    use std::string::String;

    /// borrow position for each borrowers
    struct BorrowPosition<phantom CollateralCoin, phantom LoanCoin> has key {
        collateral_coin: Coin<CollateralCoin>,
        /// Loan amount is increased by yield rate whenever a user interact
        /// with module. It can be liquidated even there is no loan amount
        /// update due to absent of interaction.
        loan_amount: u64, 
        /// Last loan amount update time, so the liquidiator should 
        /// compute the new loan amount with this last update time in consideration.
        last_update_time: u64,
    }

    /// deposit position for each depositors
    struct DepositPosition<phantom LoanCoin> has key {
        /// Deposit share amount is the fixed portion of a position from 
        /// the money pool.
        share_amount: u64,
    }

    /// Money market store for reserve coins with
    /// interest factors and configurations.
    struct MoneyPool<phantom LoanCoin> has key {
        /// Reserve coins in money market.
        loan_coin: Coin<LoanCoin>,
        /// Total loan amount.
        total_loan_amount: u64,
        /// Total share amount.
        total_share_amount: u64,
        /// Annual interest rate for borrowing.
        interest_rate: Decimal256,
        /// Minimum ltv before liquidation
        min_ltv: Decimal256,
        /// Discount rate is applied at liquidation
        discount_rate: Decimal256,
        /// Last total loan amount update time.
        last_update_time: u64,
    }

    // Responses

    /// Query response of MoneyPool
    struct MoneyPoolResponse has copy, drop {
        loan_coin_amount: u64,
        total_loan_amount: u64,
        total_share_amount: u64,
        interest_rate: Decimal256,
        min_ltv: Decimal256,
        discount_rate: Decimal256,
        last_update_time: u64,
    }

    /// Query response of BorrowPosition
    struct BorrowPositionResponse has copy, drop {
        collateral_amount: u64,
        loan_amount: u64,
        last_update_time: u64,
    }

    /// Query response of DepositPosition
    struct DepositPositionResponse has copy, drop {
        deposit_amount: u64,
    }

    // Errors
    const EMONEY_POOL_NOT_FOUND:       u64 = 1;
    const EBORROW_POSITION_NOT_FOUND:  u64 = 2;
    const EDEPOSIT_POSITION_NOT_FOUND: u64 = 3;
    const EMIN_LTV:                    u64 = 4;
    const EMIN_AMOUNT:                 u64 = 5;
    const EEXCEED_LOAN_AMOUNT:         u64 = 6;
    const EEXCEED_SHARE_AMOUNT:        u64 = 7;
    const EBORROW_POSITION_SAFE:       u64 = 8;
    const EMONEY_POOL_ALREADY_EXISTS:  u64 = 9;

    // Pool Creator Functions

    /// Create money market pool
    public entry fun create_money_pool<LoanCoin>(creator: &signer, interest_rate: String, min_ltv: String, discount_rate: String) {
        assert!(!exists<MoneyPool<LoanCoin>>(signer::address_of(creator)), error::already_exists(EMONEY_POOL_ALREADY_EXISTS));

        let (_, block_time) = block::get_block_info();
        move_to(creator, MoneyPool<LoanCoin> {
            loan_coin: coin::zero<LoanCoin>(),
            total_loan_amount: 0,
            total_share_amount: 0,
            interest_rate: decimal256::from_string(&interest_rate),
            min_ltv: decimal256::from_string(&min_ltv),
            discount_rate: decimal256::from_string(&discount_rate),
            last_update_time: block_time,
        });
    }

    // Query Functions

    #[view]
    /// Return money pool info
    public fun get_money_pool<LoanCoin>(pool_addr: address): MoneyPoolResponse acquires MoneyPool {
        let money_pool = borrow_global_mut<MoneyPool<LoanCoin>>(pool_addr);
        let (_, block_time) = block::get_block_info();
        update_money_pool(money_pool, block_time);

        MoneyPoolResponse {
            loan_coin_amount: coin::value(&money_pool.loan_coin),
            total_loan_amount: money_pool.total_loan_amount,
            total_share_amount: money_pool.total_share_amount,
            interest_rate: money_pool.interest_rate,
            min_ltv: money_pool.min_ltv,
            discount_rate: money_pool.discount_rate,
            last_update_time: money_pool.last_update_time,
        }
    }

    #[view]
    /// Return borrow position info
    public fun get_borrow_position<CollateralCoin, LoanCoin>(pool_addr: address, borrower_addr: address): BorrowPositionResponse acquires MoneyPool, BorrowPosition {
        let money_pool = borrow_global<MoneyPool<LoanCoin>>(pool_addr);
        let position = borrow_global_mut<BorrowPosition<CollateralCoin, LoanCoin>>(borrower_addr);
        let (_, block_time) = block::get_block_info();
        update_borrow_position(position, money_pool, block_time);

        BorrowPositionResponse {
            collateral_amount: coin::value(&position.collateral_coin),
            loan_amount: position.loan_amount,
            last_update_time: position.last_update_time,
        }
    }

    #[view]
    /// Return deposit position info
    public fun get_deposit_position<LoanCoin>(pool_addr: address, depositor_addr: address): DepositPositionResponse acquires MoneyPool, DepositPosition {
        let money_pool = borrow_global<MoneyPool<LoanCoin>>(pool_addr);
        let position = borrow_global<DepositPosition<LoanCoin>>(depositor_addr);

        DepositPositionResponse {
            deposit_amount: calculate_deposit_amount(position, money_pool),
        }
    }

    //
    // Update Functions
    //

    const ANNUAL_TIME_SECONDS: u64 = 31536000;

    /// Update money pool to latest loan amount with given block time
    fun update_money_pool<LoanCoin>(money_pool:&mut MoneyPool<LoanCoin>, block_time: u64) {
        let time_diff = block_time - money_pool.last_update_time;
        
        // Update total loan amount by interest rate
        money_pool.total_loan_amount = {
            let annual_interest = decimal256::mul_u64(&money_pool.interest_rate, money_pool.total_loan_amount);
            let time_ratio = decimal256::from_ratio_u64(time_diff, ANNUAL_TIME_SECONDS);
            let interest = decimal256::mul_u64(&time_ratio, annual_interest);

            money_pool.total_loan_amount + interest
        };

        money_pool.last_update_time = block_time;
    }

    /// Update borrow position to latest loan amount with the given block time
    fun update_borrow_position<CollateralCoin, LoanCoin>(position: &mut BorrowPosition<CollateralCoin, LoanCoin>, money_pool: &MoneyPool<LoanCoin>, block_time: u64) {
        let time_diff = block_time - position.last_update_time;

        // Update loan amount by interest rate
        position.loan_amount = {
            let annual_interest = decimal256::mul_u64(&money_pool.interest_rate, position.loan_amount);
            let time_ratio = decimal256::from_ratio_u64(time_diff, ANNUAL_TIME_SECONDS);
            let interest = decimal256::mul_u64(&time_ratio, annual_interest);

            position.loan_amount + interest
        };

        position.last_update_time = block_time;
    }

    /// Update deposit position to latest withdrawable deposit amount with the given block time
    fun calculate_deposit_amount<LoanCoin>(position: &DepositPosition<LoanCoin>, money_pool: &MoneyPool<LoanCoin>): u64 {
        let share_ratio = decimal256::from_ratio_u64(position.share_amount, money_pool.total_share_amount);
        let deposit_amount = decimal256::mul_u64(&share_ratio, coin::value(&money_pool.loan_coin) + money_pool.total_loan_amount);

        deposit_amount
    }

    /// Assume the price is 2 base/quote(loan/collateral), 
    /// which means "2 collateral coin == 1 loan coin"
    fun load_oracle_price<CollateralCoin, LoanCoin>(): Decimal256 {
        decimal256::from_ratio_u64(2, 1)
    }

    /// Assert current position's LTV is bigger or equal than `money_pool.min_ltv`
    fun assert_min_ltv<CollateralCoin, LoanCoin>(money_pool: &MoneyPool<LoanCoin>, position: &mut BorrowPosition<CollateralCoin, LoanCoin>) {
        let price = load_oracle_price<CollateralCoin, LoanCoin>();
        let ltv = decimal256::from_ratio_u64(
            coin::value(&position.collateral_coin),            // collateral value
            decimal256::mul_u64(&price, position.loan_amount), // loan value in collateral unit
        );
        assert!(decimal256::val(&ltv) > decimal256::val(&money_pool.min_ltv), error::internal(EMIN_LTV));
    }

    //
    // Borrower Functions
    //

    public entry fun borrow_script<CollateralCoin, LoanCoin>(borrower: &signer, pool_addr: address,  collateral_amount: u64, loan_amount: u64) acquires MoneyPool, BorrowPosition {
        let collateral_coin = coin::withdraw<CollateralCoin>(borrower, collateral_amount);
        let loan_coin = borrow<CollateralCoin, LoanCoin>(borrower, pool_addr, collateral_coin, loan_amount);
        let borrower_addr = signer::address_of(borrower);
        if (!coin::is_account_registered<LoanCoin>(borrower_addr)) {
            coin::register<LoanCoin>(borrower);
        };

        coin::deposit<LoanCoin>(borrower_addr, loan_coin);
    }

    public entry fun repay_script<CollateralCoin, LoanCoin>(borrower: &signer, pool_addr: address, repay_amount: u64, collateral_amount: u64) acquires MoneyPool, BorrowPosition {
        let repay_coin = coin::withdraw<LoanCoin>(borrower, repay_amount);
        let collateral_coin = repay<CollateralCoin, LoanCoin>(borrower, pool_addr, repay_coin, collateral_amount);
        let borrower_addr = signer::address_of(borrower);
        if (!coin::is_account_registered<CollateralCoin>(borrower_addr)) {
            coin::register<CollateralCoin>(borrower);
        };

        coin::deposit<CollateralCoin>(borrower_addr, collateral_coin);
    }

    /// borrow loan coins with collateral coin
    public fun borrow<CollateralCoin, LoanCoin>(borrower: &signer, pool_addr: address, collateral_coin: Coin<CollateralCoin>, loan_amount: u64): Coin<LoanCoin> acquires MoneyPool, BorrowPosition {
        assert!(exists<MoneyPool<LoanCoin>>(pool_addr), error::not_found(EMONEY_POOL_NOT_FOUND));

        let (_, block_time) = block::get_block_info();
        let money_pool = borrow_global_mut<MoneyPool<LoanCoin>>(pool_addr);
        update_money_pool<LoanCoin>(money_pool, block_time);

        let position = {
            let borrower_addr = signer::address_of(borrower);
            if (!exists<BorrowPosition<CollateralCoin, LoanCoin>>(borrower_addr)) {
                move_to<BorrowPosition<CollateralCoin, LoanCoin>>(borrower, BorrowPosition<CollateralCoin, LoanCoin> {
                    collateral_coin: coin::zero<CollateralCoin>(),
                    loan_amount: 0,
                    last_update_time: block_time,
                });
            };

            let position = borrow_global_mut<BorrowPosition<CollateralCoin, LoanCoin>>(borrower_addr);
            update_borrow_position<CollateralCoin, LoanCoin>(position, money_pool, block_time);
            position
        };
    
        // increase position loan amount with collateral deposit
        coin::merge(&mut position.collateral_coin, collateral_coin);
        position.loan_amount = position.loan_amount + loan_amount;

        // increase total loan amount
        money_pool.total_loan_amount = money_pool.total_loan_amount + loan_amount;
        let loan_coin = coin::extract(&mut money_pool.loan_coin, loan_amount);

        // check min_ltv
        assert_min_ltv<CollateralCoin, LoanCoin>(money_pool, position);

        loan_coin
    }

    /// repay loan coin with collateral coin withdrawal
    public fun repay<CollateralCoin, LoanCoin>(borrower: &signer, pool_addr: address, repay_coin: Coin<LoanCoin>, collateral_amount: u64): Coin<CollateralCoin> acquires MoneyPool, BorrowPosition {
        let borrower_addr = signer::address_of(borrower);

        assert!(exists<MoneyPool<LoanCoin>>(pool_addr), error::not_found(EMONEY_POOL_NOT_FOUND));
        assert!(exists<BorrowPosition<CollateralCoin, LoanCoin>>(borrower_addr), error::not_found(EBORROW_POSITION_NOT_FOUND));

        let (_, block_time) = block::get_block_info();
        let money_pool = borrow_global_mut<MoneyPool<LoanCoin>>(pool_addr);
        update_money_pool<LoanCoin>(money_pool, block_time);

        let position = borrow_global_mut<BorrowPosition<CollateralCoin, LoanCoin>>(borrower_addr);
        update_borrow_position<CollateralCoin, LoanCoin>(position, money_pool, block_time);

        let repay_amount = coin::value(&repay_coin);
        assert!(position.loan_amount >= repay_amount, error::internal(EEXCEED_LOAN_AMOUNT));

        // decrease loan amount and withdraw collteral coin
        position.loan_amount = position.loan_amount - repay_amount;
        let collateral_coin = coin::extract(&mut position.collateral_coin, collateral_amount);
        
        // repay loan coin to money pool
        coin::merge(&mut money_pool.loan_coin, repay_coin);
        money_pool.total_loan_amount = money_pool.total_loan_amount - repay_amount;
        
        // check min_ltv
        assert_min_ltv<CollateralCoin, LoanCoin>(money_pool, position);
        
        collateral_coin
    }

    //
    // Depositor Functions
    //

    public entry fun deposit_script<LoanCoin>(depositor: &signer, pool_addr: address, deposit_amount: u64) acquires MoneyPool, DepositPosition {
        let deposit_coin = coin::withdraw<LoanCoin>(depositor, deposit_amount);
        deposit<LoanCoin>(depositor, pool_addr, deposit_coin);
    }

    public entry fun withdraw_script<LoanCoin>(depositor: &signer, pool_addr: address, withdraw_amount: u64) acquires MoneyPool, DepositPosition {
        let withdraw_coin = withdraw<LoanCoin>(depositor, pool_addr, withdraw_amount);
        let depositor_addr = signer::address_of(depositor);
        if (!coin::is_account_registered<LoanCoin>(depositor_addr)) {
            coin::register<LoanCoin>(depositor);
        };

        coin::deposit<LoanCoin>(signer::address_of(depositor), withdraw_coin);
    }

    /// deposit loan coin to money pool
    public fun deposit<LoanCoin>(depositor: &signer, pool_addr: address, deposit_coin: Coin<LoanCoin>) acquires MoneyPool, DepositPosition {
        assert!(exists<MoneyPool<LoanCoin>>(pool_addr), error::not_found(EMONEY_POOL_NOT_FOUND));

        let (_, block_time) = block::get_block_info();
        let money_pool = borrow_global_mut<MoneyPool<LoanCoin>>(pool_addr);
        update_money_pool<LoanCoin>(money_pool, block_time);

        let position = {
            let depositor_addr = signer::address_of(depositor);
            if (!exists<DepositPosition<LoanCoin>>(depositor_addr)) {
                move_to<DepositPosition<LoanCoin>>(depositor, DepositPosition<LoanCoin> {
                    share_amount: 0,
                });
            };

            borrow_global_mut<DepositPosition<LoanCoin>>(depositor_addr)            
        };

        // compute deposit ratio
        let share_amount = if (money_pool.total_share_amount == 0) {
            coin::value(&deposit_coin)
        } else {
            let deposit_ratio = decimal256::from_ratio_u64(coin::value(&deposit_coin), coin::value(&money_pool.loan_coin) + money_pool.total_loan_amount);
            
            // compute deposited share amount
            decimal256::mul_u64(&deposit_ratio, money_pool.total_share_amount)
        };

        // increase deposit share amount of a position
        position.share_amount = position.share_amount + share_amount;
        money_pool.total_share_amount = money_pool.total_share_amount + share_amount;

        // deposit the coin to money_pool
        coin::merge(&mut money_pool.loan_coin, deposit_coin);
    }

    /// withdraw loan coin from the deposit position
    public fun withdraw<LoanCoin>(depositor: &signer, pool_addr: address, withdraw_amount: u64): Coin<LoanCoin> acquires MoneyPool, DepositPosition {
        let depositor_addr = signer::address_of(depositor);

        assert!(exists<MoneyPool<LoanCoin>>(pool_addr), error::not_found(EMONEY_POOL_NOT_FOUND));
        assert!(exists<DepositPosition<LoanCoin>>(depositor_addr), error::not_found(EDEPOSIT_POSITION_NOT_FOUND));

        let (_, block_time) = block::get_block_info();
        let money_pool = borrow_global_mut<MoneyPool<LoanCoin>>(pool_addr);
        update_money_pool<LoanCoin>(money_pool, block_time);

        let position = borrow_global_mut<DepositPosition<LoanCoin>>(depositor_addr);
        
        // compute withdraw ratio
        let withdraw_ratio = decimal256::from_ratio_u64(
            withdraw_amount, 
            coin::value(&money_pool.loan_coin) + money_pool.total_loan_amount,
        );

        // compute withdrawn share amount
        let share_amount = decimal256::mul_u64(&withdraw_ratio, money_pool.total_share_amount);

        // assert withdraw amount is bigger than deposit amount
        assert!(position.share_amount >= share_amount, error::internal(EEXCEED_SHARE_AMOUNT));

        // decrease withdrawn share amount
        position.share_amount = position.share_amount - share_amount;
        money_pool.total_share_amount = money_pool.total_share_amount - share_amount;

        coin::extract(&mut money_pool.loan_coin, withdraw_amount)
    }

    //
    // Liquidator Functions
    //

    public entry fun liquidate_script<CollateralCoin, LoanCoin>(
        liquidator: &signer,
        pool_addr: address,
        borrower_addr: address,
        liquidate_loan_amount: u64,
        min_liquidated_collateral_amount: u64,
    ) acquires MoneyPool, BorrowPosition {
        let liquidate_loan_coin = coin::withdraw<LoanCoin>(liquidator, liquidate_loan_amount);
        let liquidated_collateral_coin = liquidate<CollateralCoin, LoanCoin>(pool_addr, borrower_addr, liquidate_loan_coin, min_liquidated_collateral_amount);
        coin::deposit(signer::address_of(liquidator), liquidated_collateral_coin);
    }

    /// liquidate borrow position which means a liquidator buys discounted collaterals with loan coin
    public fun liquidate<CollateralCoin, LoanCoin>(
        pool_addr: address, 
        borrower_addr: address, 
        liquidate_loan_coin: Coin<LoanCoin>, 
        min_liquidated_collateral_amount: u64,
    ): Coin<CollateralCoin> acquires MoneyPool, BorrowPosition {
        assert!(exists<MoneyPool<LoanCoin>>(pool_addr), error::not_found(EMONEY_POOL_NOT_FOUND));
        assert!(exists<BorrowPosition<CollateralCoin, LoanCoin>>(borrower_addr), error::not_found(EBORROW_POSITION_NOT_FOUND));

        let (_, block_time) = block::get_block_info();
        let money_pool = borrow_global_mut<MoneyPool<LoanCoin>>(pool_addr);
        update_money_pool<LoanCoin>(money_pool, block_time);

        let position = borrow_global_mut<BorrowPosition<CollateralCoin, LoanCoin>>(borrower_addr);
        update_borrow_position<CollateralCoin, LoanCoin>(position, money_pool, block_time);

        let price = load_oracle_price<CollateralCoin, LoanCoin>();
        let ltv = decimal256::from_ratio_u64(
            coin::value(&position.collateral_coin),            // collateral value
            decimal256::mul_u64(&price, position.loan_amount), // loan value in collateral unit
        );
        assert!(decimal256::val(&ltv) < decimal256::val(&money_pool.min_ltv), error::internal(EBORROW_POSITION_SAFE));

        let liquidated_collateral_amount = {
            let liquidate_loan_amount = coin::value(&liquidate_loan_coin);
            
            // let liquidated_collateral_amount = 1 / (1 / price * (1 - discount_rate)) * liquidate_loan_amount
            // = liquidate_loan_amount * price / (1 - discount_rate)
            // = liquidate_value_in_collateral / one_minus_discount
            let one = decimal256::one();
            let one_mius_discount = decimal256::sub(&one, &money_pool.discount_rate);
            let liquidate_value_in_collateral = decimal256::mul_u64(&price, liquidate_loan_amount);
            let liquidate_value_in_collateral = decimal256::from_ratio_u64(liquidate_value_in_collateral, 1);
            ((decimal256::val(&liquidate_value_in_collateral) / decimal256::val(&one_mius_discount)) as u64)
        };

        // limit the liquidated collateral amount to position's collateral amount
        let collateral_amount = coin::value(&position.collateral_coin);
        if (liquidated_collateral_amount > collateral_amount) {
            liquidated_collateral_amount = collateral_amount;
        };

        assert!(liquidated_collateral_amount >= min_liquidated_collateral_amount, error::internal(EMIN_AMOUNT));

        coin::merge(&mut money_pool.loan_coin, liquidate_loan_coin);
        coin::extract(&mut position.collateral_coin, liquidated_collateral_amount)
    }
}