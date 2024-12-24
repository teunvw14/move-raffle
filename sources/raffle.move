/// Module: raffle
module raffle::raffle {

    use iota::balance::{Self, Balance};
    use iota::coin::{Coin};
    use iota::clock::{Clock};
    use iota::random::{Self, Random};

    // Errors
    const ERaffleNotResolvableYet: u64 = 0;
    const ERaffleNotResolved: u64 = 1;
    const ETicketDidNotWin: u64 = 2;
    const ERaffleAlreadyResolved: u64 = 3;

    /// A raffle. Token `T` will be what is used to buy tickets for that raffle.
    public struct Raffle<phantom T> has key, store {
        id: UID,
        ticket_price: u64,
        redemption_timestamp_ms: u64,
        prize_money: Balance<T>,
        sold_tickets: vector<ID>,
        winning_ticket: Option<ID> // set when the raffle is resolved
    }

    /// A struct representing a ticket in a specific raffle.
    public struct RaffleTicket has key, store{
        id: UID
    }

    /// Create a raffle
    entry fun create_raffle<T>(ticket_price: u64, duration_s: u64, clock: &Clock, ctx: &mut TxContext) {
        let redemption_timestamp_ms = clock.timestamp_ms() + 1000 * duration_s;
        let raffle = Raffle<T> {
            id: object::new(ctx),
            ticket_price,
            redemption_timestamp_ms,
            prize_money: balance::zero<T>(),
            sold_tickets: vector[],
            winning_ticket: option::none()
        };
        transfer::share_object(raffle);
    }

    public fun is_resolved<T>(raffle: &Raffle<T>): bool {
        raffle.winning_ticket.is_some()
    }

    public fun buy_ticket<T>(raffle: &mut Raffle<T>, payment: &mut  Coin<T>, ctx: &mut TxContext) {
        if (raffle.is_resolved()) {
            abort ERaffleAlreadyResolved
        };
        raffle.prize_money.join(payment.split(raffle.ticket_price, ctx).into_balance());
        let ticket_id = object::new(ctx);
        raffle.sold_tickets.push_back(ticket_id.to_inner());
        
        // Create and transfer ticket
        let ticket = RaffleTicket { id: ticket_id };
        transfer::transfer(ticket, ctx.sender());
    }

    /// Resolve the raffle (decide who wins)
    entry fun resolve<T>(raffle: &mut Raffle<T>, clock: &Clock, r: &Random, ctx: &mut TxContext) {
        let current_timestamp_ms = clock.timestamp_ms();
        if (current_timestamp_ms < raffle.redemption_timestamp_ms) {
            abort ERaffleNotResolvableYet
        };

        if (raffle.is_resolved()) {
            return // do nothing if the raffle was already resolved
        };

        let tickets_sold = raffle.sold_tickets.length();
        let winner_idx = random::new_generator(r, ctx).generate_u64_in_range(0, tickets_sold - 1);
        raffle.winning_ticket = option::some(raffle.sold_tickets[winner_idx]);
    }

    /// Claim the prize money using the winning RaffleTicket
    public fun claim_prize_money<T>(raffle: &mut Raffle<T>, ticket: RaffleTicket, ctx: &mut TxContext) {
        if (!raffle.is_resolved()) {
            abort ERaffleNotResolved
        };

        let RaffleTicket { id: winning_ticket_id } = ticket;
        if (raffle.winning_ticket != option::some(*winning_ticket_id.as_inner())) {
            abort ETicketDidNotWin
        };

        // Delete ticket
        object::delete(winning_ticket_id);

        // Send full prize_money balance to winner
        let payout_coin = raffle.prize_money.withdraw_all().into_coin(ctx);
        transfer::public_transfer(payout_coin, ctx.sender());
    }
}
