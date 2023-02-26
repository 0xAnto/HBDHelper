module anto::BirthdayBot {
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use std::error;
    use std::signer;
    use std::vector;

    /// Represents a giftpack of coins until some specified unlock time. Afterward, the recipient can claim the coins.
    struct GiftPack<phantom CoinType> has store {
        gift: Coin<CoinType>,
        birthday: u64,
        claimed: bool
        
    }

    /// Holder for a map from recipients => gift packs.
    /// There can be at most one lock per recipient.
    struct GiftHolder<phantom CoinType> has key {
        // Map from recipient address => locked coins.
        giftpacks: Table<address, GiftPack<CoinType>>,
        // Number of locks that have not yet been claimed.
        total_gifts: u64,
        // Claim events
        claim_events: EventHandle<ClaimEvent>,
    }


    /// Event emitted when a recipient claims unlocked coins.
    struct ClaimEvent has drop, store {
        recipient: address,
        amount: u64,
        claimed_at: u64,
    }

    /// No locked coins found to claim.
    const EGIFT_NOT_FOUND: u64 = 1;
    /// Lockup has not expired yet.
    const EGIFT_HAS_NOT_EXPIRED: u64 = 2;
    /// Can only create one active lock per recipient at once.
    const EGIFT_ALREADY_EXISTS: u64 = 3;
    /// The length of the recipients list doesn't match the amounts.
    const EINVALID_RECIPIENTS_LIST_LENGTH: u64 = 3;
    /// Cannot update the withdrawal address because there are still active/unclaimed locks.
    const EACTIVE_LOCKS_EXIST: u64 = 5;
    const ENOT_ADMIN: u64 = 6;
    const ENOT_INITIALIZED: u64 = 7;
    const ECLAIM_NOT_STARTED: u64 = 8;
    const EALREADY_CLAIMED: u64 = 9;
    
    
    


    /// Initialize the account to allow creating gifts.
    public entry fun initialize_gifts<CoinType>(sender: &signer) {
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == @anto, ENOT_ADMIN);
        move_to(sender, GiftHolder {
            giftpacks: table::new<address, GiftPack<CoinType>>(),
            total_gifts: 0,
            claim_events: account::new_event_handle<ClaimEvent>(sender),
        })
    }

    public entry fun add_gifts<CoinType>(
        sender: &signer, recipients: vector<address>, amounts: vector<u64>, birthdays:vector<u64>) acquires GiftHolder {
        let len = vector::length(&recipients);
        assert!(len == vector::length(&amounts) && len == vector::length(&birthdays), error::invalid_argument(EINVALID_RECIPIENTS_LIST_LENGTH));
        let i = 0;
        while (i < len) {
            let recipient = *vector::borrow(&recipients, i);
            let amount = *vector::borrow(&amounts, i);
            let birthday = *vector::borrow(&birthdays, i);
            add_gift<CoinType>(sender, recipient, amount, birthday);
            i = i + 1;
        };
    }


    public entry fun add_gift<CoinType>(
        sender: &signer, recipient: address, amount: u64, birthday: u64) acquires GiftHolder {
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == @anto, ENOT_ADMIN);
        assert!(exists<GiftHolder<CoinType>>(sender_addr), error::not_found(ENOT_INITIALIZED));
        let gift_holder = borrow_global_mut<GiftHolder<CoinType>>(sender_addr);
        let coins = coin::withdraw<CoinType>(sender, amount);
        assert!(!table::contains(&gift_holder.giftpacks, recipient), error::already_exists(EGIFT_ALREADY_EXISTS));
        table::add(&mut gift_holder.giftpacks, recipient, GiftPack<CoinType> { gift: coins, birthday, claimed: false });
        gift_holder.total_gifts = gift_holder.total_gifts + 1;
    }

    public entry fun remove_gifts<CoinType>(
        sender: &signer, recipients: vector<address>) acquires GiftHolder {
        let len = vector::length(&recipients);
        let i = 0;
        while (i < len) {
            let recipient = *vector::borrow(&recipients, i);
            remove_gift<CoinType>(sender, recipient);
            i = i + 1;
        };
    }



    public entry fun remove_gift<CoinType>(sender: &signer, recipient: address) acquires GiftHolder {
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == @anto, ENOT_ADMIN);
        assert!(exists<GiftHolder<CoinType>>(@anto), error::not_found(ENOT_INITIALIZED));
        let gift_holder = borrow_global_mut<GiftHolder<CoinType>>(@anto);
        assert!(table::contains(&gift_holder.giftpacks, recipient), error::not_found(EGIFT_NOT_FOUND));
        let GiftPack { gift, birthday: _birthday, claimed } = table::remove(&mut gift_holder.giftpacks, recipient);
        assert!(!claimed, error::unavailable(EALREADY_CLAIMED));
        gift_holder.total_gifts = gift_holder.total_gifts - 1;
        coin::deposit(sender_addr, gift);
    }

    // Function for claiming gifts
    public entry fun claim<CoinType>(recipient: &signer) acquires GiftHolder {
        assert!(exists<GiftHolder<CoinType>>(@anto), error::not_found(ENOT_INITIALIZED));
        let gift_holder = borrow_global_mut<GiftHolder<CoinType>>(@anto);
        let recipient_address = signer::address_of(recipient);
        assert!(table::contains(&gift_holder.giftpacks, recipient_address), error::not_found(EGIFT_NOT_FOUND));
        let GiftPack { gift, birthday, claimed } = table::remove(&mut gift_holder.giftpacks, recipient_address);
        assert!(!claimed, error::unavailable(EALREADY_CLAIMED));
        gift_holder.total_gifts = gift_holder.total_gifts - 1;
        let now_secs = timestamp::now_seconds();
        assert!(now_secs > birthday, error::unavailable(ECLAIM_NOT_STARTED));
        let amount = coin::value(&gift);
        if (!coin::is_account_registered<CoinType>(recipient_address)) {
            coin::register<CoinType>(recipient);
        };
        coin::deposit(recipient_address, gift);
        event::emit_event(&mut gift_holder.claim_events, ClaimEvent {
            recipient: recipient_address,
            amount,
            claimed_at: now_secs,
        });
    }
}