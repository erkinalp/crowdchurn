# frozen_string_literal: true

class FundCart::Eligibility
  Result = Struct.new(:supported, :code, :merchant_account, :custody_key, :route, keyword_init: true) do
    def supported? = supported
    def reconciling? = code == "cart_requires_reconciliation"

    def ensure_supported!
      raise FundCart::SettlementError, code unless supported?
      self
    end
  end

  ROUTE = "operator_stripe_internal_v1"

  def self.destination(fund_cart:, product:)
    return unsupported("cart_requires_reconciliation") unless fund_cart.ledger_active?
    return unsupported("cart_debt_requires_reconciliation") if fund_cart.debt_subunits.positive?
    return unsupported("currency_conversion_not_supported") unless currency_supported?(fund_cart.currency) && product.price_currency_type == fund_cart.currency
    return unsupported("unsupported_product_type") if product.is_recurring_billing? || product.is_bundle? || product.is_in_preorder_state? || product.native_type.in?(%w[fund_cart commission call coffee])
    return unsupported("inventory_reservation_unverified") if product.max_purchase_count.present? || product.base_variants.alive.where.not(max_purchase_count: nil).exists?
    # Resolve the seller's existing route, never redirect an independent merchant to the operator.
    return unsupported("external_merchant_reservation_unverified") if product.user.merchant_accounts.alive.charge_processor_alive.exists?
    return unsupported("affiliate_settlement_not_supported") if product.collaborator.present?
    account = MerchantAccount.operator(StripeChargeProcessor.charge_processor_id)
    account_result(account)
  end

  def self.contribution(purchase:, resolved_merchant: nil, processor_currency: nil)
    cart = purchase.link&.fund_cart
    return unsupported("fund_cart_missing") unless cart
    return unsupported("cart_requires_reconciliation") unless cart.ledger_active?
    return unsupported("currency_conversion_not_supported") unless currency_supported?(cart.currency) && purchase.displayed_price_currency_type.to_s == cart.currency
    return unsupported("affiliate_settlement_not_supported") if purchase.affiliate_credit_cents.to_i.positive? || purchase.affiliate.present?
    return unsupported("buyer_currency_funding_not_supported") if processor_currency.present? && processor_currency != cart.currency
    account = resolved_merchant || purchase.charge&.merchant_account || purchase.merchant_account
    result = account_result(account)
    return result unless result.supported?
    return unsupported("external_merchant_reservation_unverified") if purchase.seller.merchant_accounts.alive.charge_processor_alive.exists?
    return unsupported("buyer_currency_funding_not_supported") if purchase.buyer_presentment? && purchase.buyer_presentment_currency != cart.currency
    destinations = cart.fund_cart_items.pending.includes(:product).map { |item| destination(fund_cart: cart, product: item.product) }
    return unsupported("no_supported_destination") if destinations.empty? || destinations.none?(&:supported?)
    result
  end

  def self.account_result(account)
    return unsupported("external_merchant_reservation_unverified") unless account&.stripe_charge_processor? && account.is_managed_by_operator? && account.holder_of_funds == HolderOfFunds::GUMROAD && account.active?
    return unsupported("custody_identity_missing") if account.charge_processor_merchant_id.blank?
    Result.new(supported: true, code: nil, merchant_account: account,
               custody_key: "stripe:#{account.id}:#{account.charge_processor_merchant_id}", route: ROUTE)
  end

  def self.currency_supported?(currency)
    # The enabled custodian's Balance/payout contract is USD (BalanceTransaction::Amount and StripePayoutProcessor).
    Currency.base == Currency::USD && currency == Currency::USD
  end

  def self.unsupported(code)
    Result.new(supported: false, code:)
  end
end
