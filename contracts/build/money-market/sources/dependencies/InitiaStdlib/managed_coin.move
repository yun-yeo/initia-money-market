/// ManagedCoin is built to make a simple walkthrough of the Coins module.
/// It contains scripts you will need to initialize, mint, burn, transfer coins.
/// By utilizing this current module, a developer can create his own coin and care less about mint and burn capabilities,
module initia_std::managed_coin {
    use std::string;
    use std::error;
    use std::signer;

    use initia_std::coin::{Self, BurnCapability, FreezeCapability, MintCapability};

    //
    // Errors
    //

    /// Account has no capabilities (burn/mint).
    const ENO_CAPABILITIES: u64 = 1;

    //
    // Data structures
    //

    /// Capabilities resource storing mint and burn capabilities.
    /// The resource is stored on the account that initialized coin `CoinType`.
    struct Capabilities<phantom CoinType> has key {
        burn_cap: BurnCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>,
        mint_cap: MintCapability<CoinType>,
    }

    //
    // Public functions
    //

    /// Withdraw an `amount` of coin `CoinType` from `account` and burn it.
    public entry fun burn<CoinType>(
        account: &signer,
        amount: u64,
    ) acquires Capabilities {
        let account_addr = signer::address_of(account);

        assert!(
            exists<Capabilities<CoinType>>(account_addr),
            error::not_found(ENO_CAPABILITIES),
        );

        let capabilities = borrow_global<Capabilities<CoinType>>(account_addr);

        let to_burn = coin::withdraw<CoinType>(account, amount);
        coin::burn(to_burn, &capabilities.burn_cap);
    }

    /// Initialize new coin `CoinType` in Aptos Blockchain.
    /// Mint and Burn Capabilities will be stored under `account` in `Capabilities` resource.
    public entry fun initialize<CoinType>(
        account: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
    ) {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinType>(
            account,
            string::utf8(name),
            string::utf8(symbol),
            decimals,
        );

        move_to(account, Capabilities<CoinType> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    /// Create new coins `CoinType` and deposit them into dst_addr's account.
    public entry fun mint<CoinType>(
        account: &signer,
        dst_addr: address,
        amount: u64,
    ) acquires Capabilities {
        let account_addr = signer::address_of(account);

        assert!(
            exists<Capabilities<CoinType>>(account_addr),
            error::not_found(ENO_CAPABILITIES),
        );

        let capabilities = borrow_global<Capabilities<CoinType>>(account_addr);
        let coins_minted = coin::mint(amount, &capabilities.mint_cap);
        coin::deposit(dst_addr, coins_minted);
    }

    /// Creating a resource that stores balance of `CoinType` on user's account, withdraw and deposit event handlers.
    /// Required if user wants to start accepting deposits of `CoinType` in his account.
    public entry fun register<CoinType>(account: &signer) {
        coin::register<CoinType>(account);
    }

    //
    // Tests
    //

    #[test_only]
    struct FakeMoney {}

    #[test(source = @0xa11ce, destination = @0xb0b, mod_account = @0x1)]
    public entry fun test_end_to_end(
        source: signer,
        destination: signer,
        mod_account: signer
    ) acquires Capabilities {
        let source_addr = signer::address_of(&source);
        let destination_addr = signer::address_of(&destination);

        initialize<FakeMoney>(
            &mod_account,
            b"Fake Money",
            b"FMD",
            10,
        );
        assert!(coin::is_coin_initialized<FakeMoney>(), 0);

        coin::register<FakeMoney>(&mod_account);
        register<FakeMoney>(&source);
        register<FakeMoney>(&destination);

        mint<FakeMoney>(&mod_account, source_addr, 50);
        mint<FakeMoney>(&mod_account, destination_addr, 10);
        assert!(coin::balance<FakeMoney>(source_addr) == 50, 1);
        assert!(coin::balance<FakeMoney>(destination_addr) == 10, 2);

        let supply = coin::supply<FakeMoney>();
        assert!(supply == 60, 2);

        coin::transfer<FakeMoney>(&source, destination_addr, 10);
        assert!(coin::balance<FakeMoney>(source_addr) == 40, 3);
        assert!(coin::balance<FakeMoney>(destination_addr) == 20, 4);

        coin::transfer<FakeMoney>(&source, signer::address_of(&mod_account), 40);
        burn<FakeMoney>(&mod_account, 40);

        assert!(coin::balance<FakeMoney>(source_addr) == 0, 1);

        let new_supply = coin::supply<FakeMoney>();
        assert!(new_supply == 20, 2);
    }

    #[test(source = @0xa11ce, destination = @0xb0b, mod_account = @0x1)]
    #[expected_failure(abort_code = 0x60001, location = Self)]
    public entry fun fail_mint(
        source: signer,
        destination: signer,
        mod_account: signer,
    ) acquires Capabilities {
        let source_addr = signer::address_of(&source);

        initialize<FakeMoney>(&mod_account, b"Fake money", b"FMD", 1);
        coin::register<FakeMoney>(&mod_account);
        register<FakeMoney>(&source);
        register<FakeMoney>(&destination);

        mint<FakeMoney>(&destination, source_addr, 100);
    }

    #[test(source = @0xa11ce, destination = @0xb0b, mod_account = @0x1)]
    #[expected_failure(abort_code = 0x60001, location = Self)]
    public entry fun fail_burn(
        source: signer,
        destination: signer,
        mod_account: signer,
    ) acquires Capabilities {
        let source_addr = signer::address_of(&source);

        initialize<FakeMoney>(&mod_account, b"Fake money", b"FMD", 1);
        coin::register<FakeMoney>(&mod_account);
        register<FakeMoney>(&source);
        register<FakeMoney>(&destination);

        mint<FakeMoney>(&mod_account, source_addr, 100);
        burn<FakeMoney>(&destination, 10);
    }
}
