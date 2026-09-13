# frozen_string_literal: true

class FundCart::ContributeService
  attr_reader :purchase

  def initialize(purchase:)
    @purchase = purchase
  end

  # Called instead of crediting the contribution seller's withdrawable balance.
  def restrict_proceeds!
    cart = purchase.link.fund_cart
    result = FundCart::Eligibility.contribution(purchase:).ensure_supported!
    cart.with_lock do
      lot = cart.funding_lots.find_by(source_purchase_id: purchase.id)
      return lot if lot
      raise FundCart::SettlementError, "source_already_withdrawable" if purchase.purchase_success_balance_id.present? || purchase.balance_transactions.where(user_id: purchase.seller_id).exists?
      raise FundCart::SettlementError, "historical_source_requires_reconciliation" if purchase.successful? || purchase.created_at.to_i < cart.ledger_activated_at.to_i
      net = purchase.payment_cents - purchase.affiliate_credit_cents
      raise FundCart::SettlementError, "source_net_not_positive" unless net.positive?
      cart.funding_lots.create!(
        source_purchase: purchase, beneficiary: cart.user, source_merchant_account: result.merchant_account,
        processor: result.merchant_account.charge_processor_id, custody_key: result.custody_key,
        currency: cart.currency, currency_exponent: 2, canonical_currency: Currency.base, canonical_currency_exponent: 2,
        gross_subunits: purchase.total_transaction_cents, fee_subunits: purchase.fee_cents,
        tax_subunits: purchase.gumroad_tax_cents, affiliate_subunits: purchase.affiliate_credit_cents,
        net_subunits: net, restricted_at: Time.current,
        reserve_reference: "restricted-purchase:#{purchase.id}",
        amount_snapshot: {
          "canonical_currency" => Currency.base, "canonical_currency_exponent" => 2,
          "gross_subunits" => purchase.total_transaction_cents, "price_subunits" => purchase.price_cents,
          "fee_subunits" => purchase.fee_cents, "seller_tax_subunits" => purchase.tax_cents,
          "platform_tax_subunits" => purchase.gumroad_tax_cents, "affiliate_subunits" => purchase.affiliate_credit_cents,
          "shipping_subunits" => purchase.shipping_cents, "net_subunits" => net,
          "listed_currency" => purchase.displayed_price_currency_type, "listed_subunits" => purchase.displayed_price_cents,
          "rate_converted_to_base" => purchase.rate_converted_to_usd.to_s
        }
      )
    end
  end

  def perform
    cart = purchase.link&.fund_cart
    return unless cart && purchase.successful? && !purchase.is_test_purchase?
    lot = cart.funding_lots.find_by(source_purchase_id: purchase.id)
    # A successful historical callback cannot establish payout exclusion retroactively.
    return unless lot&.restricted_at
    cart.settlement_operations.find_or_create_by!(operation_key: "source-confirm:#{purchase.id}") do |operation|
      operation.kind = "confirm_source"
      operation.fund_cart_funding_lot = lot
      operation.purchase = purchase
    end
  end

  def self.confirm!(lot:, for_reversal: false)
    lot.reload
    return lot if lot.confirmed_at? && (for_reversal || lot.confirmation_evidence["availability_verified"] != false)
    raise FundCart::SettlementError, "source_reversal_pending" if lot.state == "frozen" && !for_reversal
    evidence = for_reversal ? FundCart::StripeCustody.confirm(lot:, for_reversal: true) : FundCart::StripeCustody.confirm(lot:)
    unless evidence["custody_key"] == lot.custody_key && evidence["currency"] == lot.currency && evidence["currency_exponent"] == lot.currency_exponent &&
        evidence["source_gross_subunits"] == lot.gross_subunits && evidence["source_net_subunits"] == lot.net_subunits &&
        evidence["payment_id"].present? && evidence["balance_transaction_id"].present? && evidence["available_at"].present?
      raise FundCart::SettlementError, "source_evidence_mismatch"
    end
    cart = lot.fund_cart
    cart.with_lock do
      lot.lock!
      if lot.confirmed_at?
        lot.update!(confirmation_evidence: evidence, available_at: Time.zone.parse(evidence.fetch("available_at")))
        cart.refresh_balance_projection!
        cart.settlement_operations.find_or_create_by!(operation_key: "allocate-source:#{lot.id}") { |operation| operation.assign_attributes(kind: "allocate", fund_cart_funding_lot: lot) }
        return lot
      end
      purchase = lot.source_purchase.reload
      raise FundCart::SettlementError, "source_payment_changed" unless evidence["payment_id"] == (purchase.charge&.processor_transaction_id || purchase.stripe_transaction_id)
      raise FundCart::SettlementError, "source_not_successful" unless purchase.successful? && !purchase.is_test_purchase?
      raise FundCart::SettlementError, "source_reversed" if !for_reversal && (purchase.stripe_refunded? || purchase.stripe_partially_refunded? || purchase.chargedback_not_reversed?)
      raise FundCart::SettlementError, "source_already_withdrawable" if purchase.purchase_success_balance_id.present? || purchase.balance_transactions.where(user_id: purchase.seller_id).exists?
      raise FundCart::SettlementError, "source_snapshot_changed" unless lot.net_subunits == purchase.payment_cents - purchase.affiliate_credit_cents && lot.gross_subunits == purchase.total_transaction_cents
      raise FundCart::SettlementError, "source_not_pending" unless lot.state.in?(%w[pending reconciling]) || (for_reversal && lot.state == "frozen")
      operation = cart.settlement_operations.create!(operation_key: "source-credit:#{purchase.id}", kind: "ledger", state: "processing", fund_cart_funding_lot: lot)
      dimensions = { currency: lot.currency, currency_exponent: lot.currency_exponent, fund_cart_funding_lot_id: lot.id,
                     user_id: lot.beneficiary_id, merchant_account_id: lot.source_merchant_account_id }
      postings = [
        dimensions.merge(account: "source_custody", amount_subunits: -lot.net_subunits),
        dimensions.merge(account: "available", amount_subunits: lot.net_subunits)
      ]
      FundCart::Ledger.post!(operation:, postings:)
      lot.update!(state: for_reversal ? "frozen" : "available", available_subunits: lot.net_subunits, confirmed_at: Time.current,
                  available_at: Time.zone.parse(evidence.fetch("available_at")), confirmation_evidence: evidence,
                  source_payment_id: evidence.fetch("payment_id"), source_balance_transaction_id: evidence.fetch("balance_transaction_id"),
                  native_currency: evidence.fetch("currency"), native_currency_exponent: evidence.fetch("currency_exponent"),
                  native_gross_subunits: evidence.fetch("source_gross_subunits"), native_net_subunits: evidence.fetch("source_net_subunits"), blocking_reason: nil)
      operation.update!(state: "completed", completed_at: Time.current)
      cart.refresh_balance_projection!
      cart.settlement_operations.create!(operation_key: "allocate-source:#{lot.id}", kind: "allocate", fund_cart_funding_lot: lot) unless for_reversal
    end
    lot
  end
end
