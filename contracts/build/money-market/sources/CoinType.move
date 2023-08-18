module my_addr::CoinType {
    use initia_std::coin;
    use initia_std::string;
    use initia_std::signer;
    use initia_std::error;

    /// only 0x1 is allowed to execute functions
    const EUNAUTHORIZED: u64 = 1;

    /// duplicated initialization check
    const EALREADY_INITIALIZED: u64 = 2;

    /// not initialized check
    const ENOT_INITIALIZED: u64 = 3;

    struct CoinA {}
    struct CoinB {}

    struct CapabilityStore<phantom CoinType> has key {
        burn_cap: coin::BurnCapability<CoinType>,
        freeze_cap: coin::FreezeCapability<CoinType>,
        mint_cap: coin::MintCapability<CoinType>,
    }

    entry fun initialize<CoinType>(creator: &signer, name: string::String, symbol: string::String, decimals: u8) {
        assert!(!exists<CapabilityStore<CoinType>>(signer::address_of(creator)), EALREADY_INITIALIZED);

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinType>(creator, name, symbol, decimals);
        move_to(creator, CapabilityStore {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    entry fun mint<CoinType>(creator: &signer, to_addr: address, amount: u64) acquires CapabilityStore {
        assert!(exists<CapabilityStore<CoinType>>(signer::address_of(creator)), error::not_found(ENOT_INITIALIZED));

        let caps = borrow_global<CapabilityStore<CoinType>>(signer::address_of(creator));
        let c = coin::mint<CoinType>(amount, &caps.mint_cap);
        coin::deposit<CoinType>(to_addr, c);
    }
}