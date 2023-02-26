module anto::GiftCoin {
    use std::string;
    use std::error;
    use std::signer;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability};


    /// Account does not have mint capability
    const ENO_CAPABILITIES: u64 = 1;
    /// Mint capability has already been delegated to this specified address
    const EALREADY_DELEGATED: u64 = 2;
    /// Cannot find delegation of mint capability to this account
    const EDELEGATION_NOT_FOUND: u64 = 3;
    const ENOT_ADMIN: u64 = 6;


    struct GiftCoin has key {}

    struct MintCapStore has key {
        mint_cap: MintCapability<GiftCoin>,
        burn_cap: BurnCapability<GiftCoin>,
    }


    /// Can only called during genesis to initialize the Aptos coin.
    fun init_module(sender: &signer){
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == @anto, ENOT_ADMIN);
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<GiftCoin>(
            sender,
            string::utf8(b"Gift Coin"),
            string::utf8(b"GIFT"),
            8, /* decimals */
            true, /* monitor_supply */
        );

        move_to(sender, MintCapStore { mint_cap, burn_cap });

        coin::destroy_freeze_cap(freeze_cap);
        
    }

    /// Only callable in tests and testnets where the core resources account exists.
    /// Create new coins and deposit them into dst_addr's account.
    public entry fun mint(
        account: &signer,
        amount: u64,
    ) acquires MintCapStore {
        let account_addr = signer::address_of(account);

        assert!(
            exists<MintCapStore>(account_addr),
            error::not_found(ENO_CAPABILITIES),
        );

        let mint_cap = &borrow_global<MintCapStore>(account_addr).mint_cap;
        let coins_minted = coin::mint<GiftCoin>(amount, mint_cap);
        if (!coin::is_account_registered<GiftCoin>(account_addr)) {
            coin::register<GiftCoin>(account);
        };
        coin::deposit<GiftCoin>(account_addr, coins_minted);


    }





}