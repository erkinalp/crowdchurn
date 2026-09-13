# frozen_string_literal: true

class FundCart::QuoteService
  ADDRESS_FIELDS = %w[full_name street_address city state zip_code country].freeze
  Quote = Struct.new(:purchase, :snapshot, :eligibility, keyword_init: true)

  def initialize(item:)
    @item = item
  end

  def perform
    cart = @item.fund_cart
    product = @item.product
    buyer = cart.user
    eligibility = FundCart::Eligibility.destination(fund_cart: cart, product:).ensure_supported!
    raise FundCart::SettlementError, "free_item_not_fundable" unless product.price_cents.positive?
    raise FundCart::SettlementError, "buyer_tax_location_required" if buyer.country.blank? || (buyer.country == "United States" && buyer.zip_code.blank?)
    options = (@item.purchase_options || {}).stringify_keys
    raise FundCart::SettlementError, "unsupported_purchase_options" if (options.keys - %w[variant_ids quantity]).any?
    quantity = Integer(options.fetch("quantity", 1))
    raise FundCart::SettlementError, "invalid_quantity" unless quantity.positive?
    variants = product.base_variants.alive.where(id: options.fetch("variant_ids", []))
    raise FundCart::SettlementError, "invalid_variants" unless variants.size == options.fetch("variant_ids", []).size
    if product.base_variants.alive.exists? && variants.empty?
      raise FundCart::SettlementError, "variant_selection_required"
    end
    purchase = product.sales.build(
      email: buyer.email, full_name: buyer.name, seller: product.user, purchaser: buyer, quantity:,
      displayed_price_currency_type: cart.currency, was_product_recommended: false,
      merchant_account: eligibility.merchant_account,
      **buyer.attributes.slice(*(ADDRESS_FIELDS - ["full_name"])).symbolize_keys
    )
    purchase.variant_attributes = variants.to_a
    purchase.perceived_price_cents = purchase.minimum_paid_price_cents
    # This existing switch skips loading/authorizing a card, not purchase, inventory, tax or address validation.
    purchase.skip_preparing_for_charge = true
    purchase.fund_cart_pricing = true
    purchase.prepare_for_charge!
    raise FundCart::SettlementError, "purchase_invalid: #{purchase.errors.full_messages.join(', ')}" if purchase.errors.any?
    raise FundCart::SettlementError, "seller_proceeds_negative" if purchase.payment_cents - purchase.affiliate_credit_cents < 0
    raise FundCart::SettlementError, "affiliate_settlement_not_supported" if purchase.affiliate_credit_cents.positive?
    purchase.save!
    Quote.new(purchase:, eligibility:, snapshot: self.class.snapshot(purchase.reload, item: @item))
  rescue StandardError
    purchase.update!(purchase_state: "failed") if purchase&.persisted? && purchase.in_progress?
    raise
  end

  def self.snapshot(purchase, item:)
    {
      "product_id" => purchase.link_id, "product_updated_at" => purchase.link.updated_at.iso8601(6),
      "product_terms" => { "price_subunits" => purchase.link.price_cents, "currency" => purchase.link.price_currency_type,
                           "seller_id" => purchase.link.user_id,
                           "shipping" => purchase.link.shipping_destinations.order(:id).map { |destination| destination.attributes.slice("id", "country_code", "one_item_rate_cents", "multiple_items_rate_cents") } },
      "seller_id" => purchase.seller_id, "beneficiary_id" => purchase.purchaser_id,
      "merchant_account_id" => purchase.merchant_account_id,
      "currency" => Currency.base, "currency_exponent" => 2,
      "listed_currency" => purchase.displayed_price_currency_type.to_s, "listed_subunits" => purchase.displayed_price_cents,
      "rate_converted_to_base" => purchase.rate_converted_to_usd.to_s,
      "amount_subunits" => purchase.total_transaction_cents, "price_subunits" => purchase.price_cents,
      "seller_tax_subunits" => purchase.tax_cents, "platform_tax_subunits" => purchase.gumroad_tax_cents,
      "shipping_subunits" => purchase.shipping_cents, "fee_subunits" => purchase.fee_cents,
      "affiliate_subunits" => purchase.affiliate_credit_cents, "quantity" => purchase.quantity,
      "variant_ids" => purchase.variant_attributes.map(&:id).sort,
      "variant_versions" => purchase.variant_attributes.sort_by(&:id).map { |variant| [variant.id, variant.updated_at.iso8601(6), variant.price_difference_cents] },
      "address" => purchase.attributes.slice(*ADDRESS_FIELDS), "purchase_options" => item.purchase_options || {}
    }
  end
end
