# frozen_string_literal: true

class FundCartPresenter
  REASONS = {
    "cart_requires_reconciliation" => "This cart needs reconciliation before contributions or purchases can proceed. Contact support; historical balances are not spendable.",
    "cart_debt_requires_reconciliation" => "A reversed contribution left an amount owed by the cart owner. Contact support to resolve it before spending resumes.",
    "currency_conversion_not_supported" => "This currency route is not supported for fund carts. Use ordinary checkout instead; funds will not be converted automatically.",
    "external_merchant_reservation_unverified" => "This merchant's payment route cannot reserve and settle fund-cart proceeds. Use ordinary checkout instead.",
    "custody_identity_missing" => "The payment custodian is not configured for fund-cart settlement. Contact support.",
    "unsupported_product_type" => "This product type is not supported for fund-cart settlement. Use ordinary checkout instead.",
    "inventory_reservation_unverified" => "Limited inventory cannot yet be reserved by a fund cart. Use ordinary checkout instead.",
    "affiliate_settlement_not_supported" => "This product's affiliate or collaborator payment route is not supported for fund carts. Use ordinary checkout instead.",
    "buyer_tax_location_required" => "The cart owner must add their country and postal code to their account before this item can be quoted.",
    "variant_selection_required" => "This item needs a version selection. Version selection is not available here yet; use ordinary checkout or contact support.",
    "invalid_variants" => "The selected version is no longer available. Use ordinary checkout or contact support to update the selection.",
    "unsupported_purchase_options" => "This item's purchase options are not supported. Use ordinary checkout or contact support.",
    "invalid_quantity" => "This item needs a valid quantity. Contact support to update its purchase options.",
    "free_item_not_fundable" => "This item does not require funding. Get it through ordinary checkout.",
    "insufficient_available_funds" => "Waiting for enough available funds to cover the full quote, including tax and shipping. Pending and reserved funds cannot be spent.",
    "settlement_reserved" => "Funds are reserved for this item. Removing it will first cancel the unexecuted reservation.",
    "settlement_processing" => "Payment is processing. Funds remain reserved until its outcome is confirmed.",
    "source_backing_unavailable" => "The original contribution's backing cannot currently be used. Funds remain reserved while its payment status is reconciled. Contact support.",
    "settlement_requires_reconciliation" => "The payment outcome needs reconciliation. The item has not been removed and its funds remain reserved. Contact support.",
    "settlement_cancellation_requested" => "Cancellation was requested. Wait for reconciliation before removing the item or reusing its funds.",
    "quote_changed" => "The item's price or options changed. A fresh quote is required before it can be purchased.",
    "custody_changed" => "The merchant's payment route changed. Contact support to recheck settlement eligibility.",
    "awaiting_allocation" => "Waiting for a complete quote and eligible available funds. Tax, shipping and required purchase options are checked before reservation.",
    "only_pending_items_can_be_removed" => "Only pending items can be removed",
  }.freeze

  def initialize(fund_cart)
    @fund_cart = fund_cart
  end

  def api_props
    {
      id: @fund_cart.external_id,
      product_id: @fund_cart.link.external_id,
      product_name: @fund_cart.link.name,
      pending_items_count: @fund_cart.fund_cart_items.pending.count,
      purchased_items_count: @fund_cart.fund_cart_items.purchased.count,
    }.merge(funds_props)
  end

  def funds_props
    # Use the allocator's lock so amounts cannot straddle a reservation.
    @fund_cart.with_lock do
      available = @fund_cart.available_subunits
      values = {
        available: available,
        pending: @fund_cart.pending_subunits,
        reserved: @fund_cart.reserved_subunits,
        debt: @fund_cart.debt_subunits,
      }
      {
        # Never expose a historical or stale counter as spendable credit.
        balance_subunits: available,
        currency: @fund_cart.currency,
        currency_exponent: self.class.currency_exponent(@fund_cart.currency),
        ledger_state: @fund_cart.ledger_state,
        amounts: values.transform_values { |value| self.class.amount(subunits: value, currency: @fund_cart.currency) },
        **values.transform_keys { |key| :"#{key}_subunits" },
      }
    end
  end

  def item_props(item)
    settlement = item.settlements.order(id: :desc).first
    active = item.settlements.where.not(active_item_id: nil).order(id: :desc).first
    eligibility = FundCart::Eligibility.destination(fund_cart: @fund_cart, product: item.product)
    reason_code = if item.state == "pending"
      if active&.cancel_requested_at?
        "settlement_cancellation_requested"
      elsif active&.state == "reserved"
        "settlement_reserved"
      elsif active&.state == "processing"
        "settlement_processing"
      elsif active&.state == "reconciling"
        active.blocking_reason.presence || "settlement_requires_reconciliation"
      else
        eligibility.code || item.blocking_reason.presence || "awaiting_allocation"
      end
    end
    reconciling = active&.state == "reconciling" || eligibility.code.in?(%w[cart_requires_reconciliation cart_debt_requires_reconciliation])
    route_reason = active&.blocking_reason.presence || eligibility.code
    {
      id: item.external_id,
      product_id: item.product.external_id,
      product_name: item.product.name,
      product_price_cents: item.product.price_cents,
      product_native_type: item.product.native_type,
      product_currency: item.product.price_currency_type,
      product_price: self.class.amount(subunits: item.product.price_cents, currency: item.product.price_currency_type),
      state: item.state,
      purchased_at: item.purchased_at&.iso8601,
      created_at: item.created_at.iso8601,
      pending_reason: reason_code && self.class.reason(reason_code),
      route_status: {
        state: reconciling ? "reconciling" : eligibility.supported? ? "supported" : "unsupported",
        route: active&.route || eligibility.route,
        reason: route_reason && self.class.reason(route_reason),
      },
      can_remove: item.state == "pending" && (active.nil? || active.state == "reserved"),
      can_request_cancellation: item.state == "pending" && active&.state.in?(%w[processing reconciling]) && !active.cancel_requested_at?,
      removal_requires_cancellation: item.state == "pending" && active.present?,
      settlement: settlement && {
        id: settlement.external_id,
        state: settlement.state,
        cancel_requested: settlement.cancel_requested_at?,
        amount: self.class.amount(subunits: settlement.amount_subunits, currency: settlement.currency, currency_exponent: settlement.currency_exponent),
      },
    }
  end

  def self.reason(code)
    message = REASONS[code]
    message ||= if code.start_with?("purchase_invalid:")
      "The item could not be quoted: #{code.delete_prefix('purchase_invalid:').strip}. Review the cart owner's address and the product's required options."
    else
      "This item needs review before funds can be spent. Contact support with reason: #{code}."
    end
    { code:, message: }
  end

  def self.currency_exponent(currency)
    Currency.subunit_to_unit(currency).to_i.to_s.length - 1
  end

  # Decimal strings preserve base units beyond JavaScript's safe integer range.
  def self.amount(subunits:, currency:, currency_exponent: self.currency_exponent(currency))
    units = subunits.to_i
    digits = units.abs.to_s.rjust(currency_exponent + 1, "0")
    decimal = currency_exponent.zero? ? digits : "#{digits[0...-currency_exponent]}.#{digits[-currency_exponent..]}"
    { subunits: units.to_s, currency:, currency_exponent:, formatted: "#{'-' if units.negative?}#{decimal} #{currency.upcase}" }
  end
end
