/// This module provides interfaces to allow CosmosMessage 
/// execution after the move execution finished.
module initia_std::cosmos {
    use std::signer;
    use std::string::{Self, String};

    public entry fun delegate<CoinType>(
        delegator: &signer, 
        validator: String, 
        amount: u64,
    ) {
        delegate_internal<CoinType>(
            signer::address_of(delegator),
            *string::bytes(&validator),
            amount,
        )
    }

    public entry fun fund_community_pool<CoinType>(
        sender: &signer, 
        amount: u64,
    ) {
        fund_community_pool_internal<CoinType>(
            signer::address_of(sender),
            amount,
        )
    }

    /// ICS20 ibc transfer
    /// https://github.com/cosmos/ibc/tree/main/spec/app/ics-020-fungible-token-transfer
    public entry fun transfer<CoinType>(
        sender: &signer,
        receiver: String,
        token_amount: u64,
        source_port: String,
        source_channel: String,
        revision_number: u64,
        revision_height: u64,
        timeout_timestamp: u64,
        memo: String,
    ) {
        transfer_internal<CoinType>(
            signer::address_of(sender),
            *string::bytes(&receiver),
            token_amount,
            *string::bytes(&source_port),
            *string::bytes(&source_channel),
            revision_number,
            revision_height,
            timeout_timestamp,
            *string::bytes(&memo),
        )
    }

    /// ICS29 ibc relayer fee
    /// https://github.com/cosmos/ibc/tree/main/spec/app/ics-029-fee-payment
    public entry fun pay_fee<RecvCoinType, AckCoinType, TimeoutCoinType>(
        sender: &signer,
        source_port: String,
        source_channel: String,
        recv_fee_amount: u64,
        ack_fee_amount: u64,
        timeout_fee_amount: u64,
    ) {
        pay_fee_internal<RecvCoinType, AckCoinType, TimeoutCoinType>(
            signer::address_of(sender),
            *string::bytes(&source_port),
            *string::bytes(&source_channel),
            recv_fee_amount,
            ack_fee_amount,
            timeout_fee_amount,
        )
    }


    native fun delegate_internal<CoinType>(
        delegator: address, 
        validator: vector<u8>, 
        amount: u64,
    );

    native fun fund_community_pool_internal<CoinType>(
        sender: address, 
        amount: u64,
    );

    native fun transfer_internal<CoinType>(
        sender: address,
        receiver: vector<u8>,
        token_amount: u64,
        source_port: vector<u8>,
        source_channel: vector<u8>,
        revision_number: u64,
        revision_height: u64,
        timeout_timestamp: u64,
        memo: vector<u8>,
    );

    native fun pay_fee_internal<RecvCoinType, AckCoinType, TiemoutCoinType>(
        sender: address,
        source_port: vector<u8>,
        source_channel: vector<u8>,
        recv_fee_amount: u64,
        ack_fee_amount: u64,
        timeout_fee_amount: u64,
    );
}