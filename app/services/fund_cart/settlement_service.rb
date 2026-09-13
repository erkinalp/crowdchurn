# frozen_string_literal: true

class FundCart::SettlementService
  def initialize(settlement:)
    @settlement = settlement
  end

  def perform
    return @settlement if @settlement.reload.state == "settled"
    raise FundCart::SettlementError, "unsupported_settlement_route" unless @settlement.route == FundCart::Eligibility::ROUTE
    purchase = @settlement.purchase
    # Balance selection stays outside the cart transaction, as required by BalanceTransaction's lock contract.
    balance = select_seller_balance(purchase)
    balance.with_lock do
      raise FundCart::SettlementError, "seller_balance_not_payable" unless balance.unpaid?
      @settlement.fund_cart.with_lock do
        @settlement.fund_cart_item.lock!
        @settlement.lock!
        return @settlement if @settlement.state == "settled"
        raise FundCart::SettlementError, "settlement_requires_reconciliation" unless @settlement.state == "reserved"
        eligibility = FundCart::Eligibility.destination(fund_cart: @settlement.fund_cart, product: purchase.link.reload).ensure_supported!
        raise FundCart::SettlementError, "custody_changed" unless eligibility.custody_key == @settlement.custody_key
        raise FundCart::SettlementError, "quote_changed" unless FundCart::QuoteService.snapshot(purchase.reload, item: @settlement.fund_cart_item) == @settlement.quote_snapshot
        raise FundCart::SettlementError, "destination_not_pending" unless purchase.in_progress? && @settlement.fund_cart_item.state == "pending"
        allocations = @settlement.allocations.order(:fund_cart_funding_lot_id).to_a
        allocations.each { |allocation| allocation.funding_lot.lock! }
        raise FundCart::SettlementError, "allocation_total_mismatch" unless allocations.sum(&:amount_subunits) == @settlement.amount_subunits
        allocations.each do |allocation|
          lot = allocation.funding_lot
          reserved_ledger = lot.ledger_entries.where(account: "reserved", currency: lot.currency).sum(:amount_subunits)
          unless allocation.state == "reserved" && lot.spendable? && lot.custody_key == @settlement.custody_key && lot.currency == @settlement.currency && lot.reserved_subunits >= allocation.amount_subunits && reserved_ledger >= allocation.amount_subunits
            raise FundCart::SettlementError, "source_backing_unavailable"
          end
        end
        operation = @settlement.operations.create!(fund_cart: @settlement.fund_cart, operation_key: "settle:#{@settlement.operation_key}", kind: "ledger", state: "processing")
        postings = allocations.map do |allocation|
          lot = allocation.funding_lot
          lot.update!(reserved_subunits: lot.reserved_subunits - allocation.amount_subunits, spent_subunits: lot.spent_subunits + allocation.amount_subunits)
          allocation.update!(state: "consumed")
          dimensions.merge(account: "reserved", amount_subunits: -allocation.amount_subunits,
                           fund_cart_funding_lot_id: lot.id, user_id: lot.beneficiary_id, merchant_account_id: lot.source_merchant_account_id)
        end
        net = purchase.payment_cents - purchase.affiliate_credit_cents
        postings << dimensions.merge(account: "seller_payable", user_id: purchase.seller_id, amount_subunits: net)
        postings << dimensions.merge(account: "platform_fee", amount_subunits: purchase.fee_cents)
        postings << dimensions.merge(account: "platform_tax", amount_subunits: purchase.gumroad_tax_cents)
        postings << dimensions.merge(account: "affiliate_payable", user_id: purchase.affiliate&.affiliate_user_id, amount_subunits: purchase.affiliate_credit_cents)
        FundCart::Ledger.post!(operation:, postings:)
        issued = BalanceTransaction::Amount.new(currency: @settlement.currency, gross_cents: purchase.total_transaction_cents, net_cents: net)
        transaction = BalanceTransaction.create!(user: purchase.seller, merchant_account: @settlement.destination_merchant_account,
                                                 purchase:, issued_amount: issued, holding_amount: issued, update_user_balance: false)
        balance.update!(amount_cents: balance.amount_cents + net, holding_amount_cents: balance.holding_amount_cents + net)
        transaction.update!(balance:)
        purchase.update!(purchase_success_balance: balance, succeeded_at: Time.current)
        operation.update!(state: "completed", completed_at: Time.current, external_references: { "seller_balance_transaction_id" => transaction.id })
        @settlement.update!(state: "settled", settled_at: Time.current, blocking_reason: nil,
                            receipt: { "operation_key" => @settlement.operation_key, "currency" => @settlement.currency,
                                       "amount_subunits" => @settlement.amount_subunits.to_i, "custody_key" => @settlement.custody_key,
                                       "seller_balance_transaction_id" => transaction.id })
        @settlement.fund_cart_item.mark_purchased!(purchase)
        @settlement.fund_cart_item.update!(blocking_reason: nil)
        @settlement.fund_cart.refresh_balance_projection!
        @settlement.operations.create!(fund_cart: @settlement.fund_cart, operation_key: "fulfill:#{@settlement.operation_key}", kind: "fulfill", purchase:)
      end
    end
    @settlement
  rescue FundCart::SettlementError => error
    @settlement.update!(state: "reconciling", blocking_reason: error.code) if @settlement.reload.state == "reserved"
    raise
  end

  private
    def dimensions
      { currency: @settlement.currency, currency_exponent: @settlement.currency_exponent,
        fund_cart_settlement_id: @settlement.id, merchant_account_id: @settlement.destination_merchant_account_id }
    end

    def select_seller_balance(purchase)
      purchase.succeeded_at ||= Time.current
      BalanceTransaction.new(user: purchase.seller, merchant_account: @settlement.destination_merchant_account,
                             purchase:, issued_amount_currency: @settlement.currency, holding_amount_currency: @settlement.currency).find_or_create_balance
    end
end
