# frozen_string_literal: true

module Product::Prices
  include BasePrice::Shared
  include CurrencyHelper

  # Public: Alias for default_price_cents in order to hide the price_cents column, which isn't used anymore in favor of the Price model.
  def price_cents
    default_price_cents
  end

  # Public: Returns a single price for the product that can be used in generic situations where rent vs. buy is not indicated.
  # Accepts an optional buyer_currency parameter to resolve price based on pricing_mode.
  #
  # buyer_currency - The currency the buyer wants to pay in (optional). When nil, returns the product's default price.
  #
  # Returns Integer price in cents/units for the resolved currency.
  def default_price_cents(buyer_currency: nil)
    rent_only? ? rental_price_cents(buyer_currency:) : buy_price_cents(buyer_currency:)
  end

  # Public: Returns the buy price in cents, optionally resolved for a buyer's currency.
  #
  # buyer_currency - The currency the buyer wants to pay in (optional).
  #
  # Returns Integer price in cents/units.
  def buy_price_cents(buyer_currency: nil)
    # Do not query for the associated Price objects if the product isn't persisted yet since those will always return empty results.
    # All products are created with a price_cents and this attribute should be read until the product is persisted, after which the
    # associated Price(s) determine the product's price(s).
    return read_attribute(:price_cents) unless persisted?

    resolved = resolve_price_for_buyer(buyer_currency:, is_rental: false)
    return resolved[:price_cents] if resolved && buyable?

    nil
  end

  # Public: Returns the rental price in cents, optionally resolved for a buyer's currency.
  #
  # buyer_currency - The currency the buyer wants to pay in (optional).
  #
  # Returns Integer price in cents/units or nil.
  def rental_price_cents(buyer_currency: nil)
    return read_attribute(:rental_price_cents) unless persisted?
    return nil unless rentable?

    resolved = resolve_price_for_buyer(buyer_currency:, is_rental: true)
    resolved&.dig(:price_cents)
  end

  # Public: Returns the default Price object for this product.
  # Accepts an optional buyer_currency parameter to resolve price based on pricing_mode.
  #
  # buyer_currency - The currency the buyer wants to pay in (optional).
  #
  # Returns Price object or nil.
  def default_price(buyer_currency: nil)
    target_currency = resolve_target_currency(buyer_currency)
    is_rental = rent_only?

    if is_rental
      return alive_prices.where(currency: target_currency).select(&:is_rental?).last
    end

    relevant_prices = alive_prices.where(currency: target_currency).select(&:is_buy?)
    relevant_prices = relevant_prices.select(&:is_default_recurrence?) if is_recurring_billing && subscription_duration.present?
    relevant_prices.last
  end

  # Public: Find an explicit price for a specific currency.
  #
  # currency_type - The currency to look up (e.g., "usd", "eur").
  # recurrence    - The recurrence period (optional, for subscriptions).
  # is_rental     - Whether to look for rental prices (default: false).
  #
  # Returns Price object or nil if no explicit price exists for that currency.
  def price_for_currency(currency_type, recurrence: nil, is_rental: false)
    return nil if currency_type.blank?

    normalized_currency = currency_type.to_s.downcase
    scoped_prices = is_rental ? alive_prices.is_rental : alive_prices.is_buy
    scoped_prices = scoped_prices.where(currency: normalized_currency)
    scoped_prices = scoped_prices.where(recurrence:) if recurrence.present?
    scoped_prices.last
  end

  # Public: Resolve price for a buyer based on pricing_mode.
  # Returns a hash with price information including whether conversion is needed.
  #
  # buyer_currency - The currency the buyer wants to pay in.
  # recurrence     - The recurrence period (optional, for subscriptions).
  # is_rental      - Whether to resolve rental price (default: false).
  #
  # Returns Hash with :price_cents, :currency, :conversion_needed, :source_currency keys.
  def resolve_price_for_buyer(buyer_currency: nil, recurrence: nil, is_rental: false)
    # Use product's default currency if buyer currency not specified
    target_currency = buyer_currency.present? ? buyer_currency.to_s.downcase : price_currency_type.to_s.downcase
    default_recurrence = recurrence || (is_recurring_billing ? subscription_duration.to_s : nil)

    case pricing_mode&.to_sym
    when :gross
      resolve_gross_mode_price(target_currency, default_recurrence, is_rental)
    when :multi_currency
      resolve_multi_currency_mode_price(target_currency, default_recurrence, is_rental)
    else # :legacy or nil (default)
      resolve_legacy_mode_price(target_currency, default_recurrence, is_rental)
    end
  end

  # Public: Check if an explicit price exists for a given currency.
  #
  # currency_type - The currency to check.
  #
  # Returns Boolean.
  def has_price_for_currency?(currency_type)
    price_for_currency(currency_type).present?
  end

  # Public: Get the minimum price for a given currency from config.
  #
  # currency_type - The currency to get minimum for.
  #
  # Returns Integer minimum price in cents/units.
  def min_price_for_currency(currency_type)
    normalized = currency_type.to_s.downcase
    currency_config = CURRENCY_CHOICES[normalized] || CRYPTO_CURRENCIES[normalized]
    currency_config&.dig("min_price") || currency_config&.dig(:min_price) || 0
  end

  # Public: Check if a currency uses single units (no cents subdivision).
  #
  # currency_type - The currency to check.
  #
  # Returns Boolean.
  def currency_single_unit?(currency_type)
    normalized = currency_type.to_s.downcase
    currency_config = CURRENCY_CHOICES[normalized] || CRYPTO_CURRENCIES[normalized]
    currency_config&.key?("single_unit") || currency_config&.key?(:single_unit) || false
  end

  # Public: Sets the buy price of the product to price_cents. If the product is already persisted then it changes the Price(s) associated with the
  # product to achieve that. If the product hasn't been persisted yet it simply sets the price_cents attribute and relies on associate_price to
  # create and associated the proper Price(s) object. If the product is a tiered membership product, it does not create or update a new price since
  # these prices are set on the variant.
  def price_cents=(price_cents)
    return super(price_cents) if !persisted? || is_tiered_membership

    create_or_update_new_price!(price_cents:, recurrence: subscription_duration.try(:to_s), is_rental: false)
  end

  def rental_price_cents=(rental_price_cents)
    return super(rental_price_cents) unless persisted?

    create_or_update_new_price!(price_cents: rental_price_cents, recurrence: subscription_duration.try(:to_s), is_rental: true)
  end

  def set_customizable_price
    return if is_tiered_membership
    return unless default_price_cents == 0
    return if variant_categories_alive.joins(:variants).merge(BaseVariant.alive).sum("base_variants.price_difference_cents") > 0
    update_column(:customizable_price, true)
  end

  def price_range=(price)
    return unless price

    price_string = price.to_s
    self.price_cents = clean_price(price_string)
    write_customizable_price(price_string)
  end

  def rental_price_range=(rental_price_string)
    self.rental_price_cents = rental_price_string.present? ? clean_price(rental_price_string) : nil
    write_customizable_price(rental_price_string) if rent_only?
  end

  def suggested_price=(price)
    self.suggested_price_cents = price.present? ? clean_price(price.to_s) : nil
  end

  def format_price(price)
    price == "$0.99" ? "99¢" : price
  end

  def price_formatted
    format_price(display_price)
  end

  def rental_price_formatted
    format_price(rental_display_price)
  end

  def price_formatted_verbose
    "#{price_formatted}#{show_customizable_price_indicator? ? '+' : ''}#{is_recurring_billing ? " #{recurrence_long_indicator(display_recurrence)}" : ''}"
  end

  def price_formatted_including_rental_verbose
    return price_formatted_verbose unless buy_and_rent?

    "#{rental_price_formatted}#{show_customizable_price_indicator? ? '+' : ''} / #{price_formatted}#{show_customizable_price_indicator? ? '+' : ''}"
  end

  def suggested_price_formatted
    attrs = { no_cents_if_whole: true, symbol: false }
    MoneyFormatter.format(suggested_price_cents, price_currency_type.to_sym, attrs)
  end

  def base_price_formatted_without_dollar_sign
    display_price_for_price_cents(display_base_price_cents, symbol: false)
  end

  def price_formatted_without_dollar_sign
    display_price(symbol: false)
  end

  def rental_price_formatted_without_dollar_sign
    MoneyFormatter.format(rental_price_cents, price_currency_type.to_sym, no_cents_if_whole: true, symbol: false)
  end

  def currency_symbol
    symbol_for(price_currency_type)
  end

  def currency
    CURRENCY_CHOICES[price_currency_type] || CRYPTO_CURRENCIES[price_currency_type.to_s.downcase]
  end

  # Returns true if the product is priced in a cryptocurrency
  def crypto_priced?
    is_crypto_currency?(price_currency_type)
  end

  # Returns true if the product is priced in a volatile cryptocurrency (non-stablecoin)
  def volatile_crypto_priced?
    crypto_priced? && !is_stablecoin?(price_currency_type)
  end

  # Returns the decimal precision for the product's currency
  def price_decimals
    Currency.decimals_for(price_currency_type)
  end

  # Returns the display decimal precision for the product's currency
  def price_display_decimals
    Currency.display_decimals_for(price_currency_type)
  end

  def min_price_formatted
    MoneyFormatter.format(currency["min_price"], price_currency_type.to_sym, no_cents_if_whole: true, symbol: true)
  end

  # used by links_controller and api/links_controller to validate the price of the product against all its offer codes
  # if more routes open up to change product price, make sure to wrap in transaction and use this method
  def validate_product_price_against_all_offer_codes?
    all_alive_offer_codes = product_and_universal_offer_codes
    all_alive_offer_codes.each do |offer_code|
      price_after_code = default_price_cents - offer_code.amount_off(default_price_cents)
      next if price_after_code <= 0 || price_after_code >= currency["min_price"]

      errors.add(:base, "An existing discount code puts the price of this product below the #{min_price_formatted} minimum after discount.")
      return false
    end
    true
  end

  def suggested_price_greater_than_price
    return if suggested_price_cents.blank? || !customizable_price || suggested_price_cents >= default_price_cents

    errors.add(:base, "The suggested price you entered was too low.")
  end

  def write_customizable_price(price_string)
    return if is_tiered_membership
    price_customizable = price_string[-1, 1] == "+" || price_cents == 0
    self.customizable_price = price_customizable
  end

  def display_base_price_cents
    is_tiered_membership ? (lowest_tier_price.price_cents || 0) : default_price_cents
  end

  def display_price_cents(for_default_duration: false)
    if is_tiered_membership?
      lowest_tier_price(for_default_duration:).price_cents || 0
    else
      default_price_cents + (lowest_variant_price_difference_cents || 0)
    end
  end

  def display_price(additional_attrs = {})
    display_price_for_price_cents(display_price_cents, additional_attrs)
  end

  def rental_display_price(additional_attrs = {})
    display_price_for_price_cents(rental_price_cents, additional_attrs)
  end

  def display_price_for_price_cents(price_cents, additional_attrs = {})
    attrs = { no_cents_if_whole: true, symbol: true }.merge(additional_attrs)
    MoneyFormatter.format(price_cents, price_currency_type.to_sym, attrs)
  end

  def price_for_recurrence(recurrence)
    prices.alive.is_buy.where(recurrence:).last
  end

  def price_cents_for_recurrence(recurrence)
    price_for_recurrence(recurrence).try(:price_cents)
  end

  def price_formatted_without_dollar_sign_for_recurrence(recurrence)
    price_cents = price_cents_for_recurrence(recurrence)
    return "" if price_cents.blank?

    display_price_for_price_cents(price_cents, symbol: false)
  end

  def has_price_for_recurrence?(recurrence)
    price_for_recurrence(recurrence).present?
  end

  def suggested_price_formatted_without_dollar_sign_for_recurrence(recurrence)
    suggested_price_cents = suggested_price_cents_for_recurrence(recurrence)
    return nil if suggested_price_cents.blank?

    display_price_for_price_cents(suggested_price_cents, symbol: false)
  end

  def save_subscription_prices_and_duration!(recurrence_price_values:, subscription_duration:)
    ActiveRecord::Base.transaction do
      self.subscription_duration = subscription_duration

      enabled_recurrences = recurrence_price_values.select { |_, attributes| attributes[:enabled].to_s == "true" }

      unless subscription_duration.to_s.in?(enabled_recurrences)
        errors.add(:base, "Please provide a price for the default payment option.")
        raise Link::LinkInvalid
      end

      save_recurring_prices!(recurrence_price_values)
    end
  end

  def has_multiple_recurrences?
    return false unless is_recurring_billing

    prices.alive.is_buy.select(:recurrence).distinct.count > 1
  end

  def available_price_cents
    available_prices =
      if is_tiered_membership?
        VariantPrice.where(variant_id: tiers.pluck(:id)).alive.is_buy.pluck(:price_cents)
      elsif current_base_variants.present?
        base_price = default_price_cents
        current_base_variants.pluck(:price_difference_cents).map { |difference| base_price + difference.to_i }
      else
        prices.alive.is_buy.pluck(:price_cents)
      end

    available_prices.uniq
  end

  private
    # Private: Called only on create to instantiate Price object(s) and associate it to the newly created product.
    def associate_price
      # for tiered memberships, price is set at the tier level
      return if is_tiered_membership

      price_cents = read_attribute(:price_cents)
      if price_cents.blank?
        errors.add(:base, "New products should be created with a price_cents")
        raise Link::LinkInvalid
      end

      price = Price.new
      price.price_cents = price_cents
      price.recurrence = subscription_duration.try(:to_s)
      price.currency = price_currency_type
      prices << price

      return unless rentable?

      rental_price_cents = read_attribute(:rental_price_cents)
      rental_price = Price.new
      rental_price.price_cents = rental_price_cents
      rental_price.currency = price_currency_type
      rental_price.is_rental = true
      prices << rental_price
    end

    def delete_unused_prices
      if buy_only?
        prices.alive.is_rental.each(&:mark_deleted!)
      elsif rent_only?
        prices.alive.is_buy.each(&:mark_deleted!)
      end
    end

    def suggested_price_cents_for_recurrence(recurrence)
      suggested_price_cents = price_cents_for_recurrence(recurrence)
      return suggested_price_cents if suggested_price_cents.present?

      default_price = self.default_price
      return nil if default_price.blank?

      number_of_months_in_default_price_recurrence = BasePrice::Recurrence.number_of_months_in_recurrence(default_price.recurrence)
      default_price_cents = default_price.price_cents
      number_of_months_in_recurrence = BasePrice::Recurrence.number_of_months_in_recurrence(recurrence)
      suggested_price_cents = (default_price_cents / number_of_months_in_default_price_recurrence.to_f) * number_of_months_in_recurrence
      suggested_price_cents
    end

    def show_customizable_price_indicator?
      return customizable_price unless is_tiered_membership

      # for tiered products, show `+` in formatted price if:
      # 1. there are multiple tiers, or
      # 2. any tiers have PWYW enabled, or
      # 3. there's only 1 tier but it has multiple prices
      tiers.size > 1 || tiers.where(customizable_price: true).exists? || default_tier.prices.alive.is_buy.size > 1
    end

    def lowest_tier_price(for_default_duration: false)
      return unless is_tiered_membership

      prices = VariantPrice.where(variant_id: tiers.map(&:id)).alive.is_buy
      prices = prices.where(recurrence: subscription_duration) if for_default_duration
      prices.order("price_cents asc").take ||
        default_tier.prices.is_buy.build(price_cents: 0, recurrence: subscription_duration)
    end

    def lowest_variant_price_difference_cents
      return if is_tiered_membership?
      lowest_variant = current_base_variants.order(price_difference_cents: :asc).first
      lowest_variant&.price_difference_cents
    end

    def display_recurrence
      is_tiered_membership && lowest_tier_price ? lowest_tier_price.recurrence : subscription_duration
    end

    def prices_to_validate
      if persisted?
        prices.alive.where(currency: price_currency_type).pluck(:price_cents)
      else
        price_cents_to_validate = []
        price_cents_to_validate << buy_price_cents if buyable?
        price_cents_to_validate << rental_price_cents if rentable?
        price_cents_to_validate
      end
    end

    # Private: Resolve the target currency based on pricing mode and buyer currency.
    #
    # buyer_currency - The currency the buyer wants to pay in (optional).
    #
    # Returns String currency code.
    def resolve_target_currency(buyer_currency)
      return price_currency_type.to_s.downcase if buyer_currency.blank?

      target = buyer_currency.to_s.downcase

      case pricing_mode&.to_sym
      when :multi_currency
        # In multi_currency mode, check if we have an explicit price for buyer's currency
        # If not, fall back to product's default currency
        has_price_for_currency?(target) ? target : price_currency_type.to_s.downcase
      when :gross
        # In gross mode, always use buyer's currency (FX converted to maintain purchasing power)
        target
      else # :legacy or nil
        # In legacy mode, always use product's currency (conversion at checkout)
        price_currency_type.to_s.downcase
      end
    end

    # Private: Resolve price in legacy mode.
    # Returns the product's price in its default currency. Conversion happens at checkout.
    #
    # target_currency - The buyer's desired currency (ignored in legacy mode).
    # recurrence      - The recurrence period for subscriptions.
    # is_rental       - Whether to get rental price.
    #
    # Returns Hash with price information.
    def resolve_legacy_mode_price(target_currency, recurrence, is_rental)
      product_currency = price_currency_type.to_s.downcase
      price = find_base_price(product_currency, recurrence, is_rental)

      return nil if price.nil?

      {
        price_cents: price.price_cents,
        currency: product_currency,
        source_currency: product_currency,
        conversion_needed: target_currency != product_currency,
        pricing_mode: :legacy
      }
    end

    # Private: Resolve price in gross mode.
    # Converts the tax-inclusive price to the buyer's currency using FX rates.
    # Example: $100 USD product shows as €92 EUR for EUR buyer (at 0.92 rate).
    #
    # target_currency - The buyer's desired currency.
    # recurrence      - The recurrence period for subscriptions.
    # is_rental       - Whether to get rental price.
    #
    # Returns Hash with price information.
    def resolve_gross_mode_price(target_currency, recurrence, is_rental)
      product_currency = price_currency_type.to_s.downcase
      base_price = find_base_price(product_currency, recurrence, is_rental)

      return nil if base_price.nil?

      # In gross mode, convert the tax-inclusive price to the buyer's currency
      # using FX rates to maintain equivalent purchasing power
      if target_currency.to_s.downcase == product_currency
        # Same currency, no conversion needed
        price_cents = base_price.price_cents
      else
        # Convert: source -> base currency -> target currency
        # First convert to base currency units
        base_units = get_base_currency_units(product_currency, base_price.price_cents)
        # Then convert from base currency to target currency
        price_cents = base_currency_to_display_currency(target_currency, base_units)
      end

      {
        price_cents: price_cents,
        currency: target_currency,
        source_currency: product_currency,
        conversion_needed: target_currency.to_s.downcase != product_currency,
        pricing_mode: :gross
      }
    end

    # Private: Resolve price in multi_currency mode.
    # Looks up explicit price for buyer's currency, falls back to default if not found.
    #
    # target_currency - The buyer's desired currency.
    # recurrence      - The recurrence period for subscriptions.
    # is_rental       - Whether to get rental price.
    #
    # Returns Hash with price information.
    def resolve_multi_currency_mode_price(target_currency, recurrence, is_rental)
      product_currency = price_currency_type.to_s.downcase

      # First, try to find an explicit price for the buyer's currency
      explicit_price = price_for_currency(target_currency, recurrence:, is_rental:)

      if explicit_price.present?
        return {
          price_cents: explicit_price.price_cents,
          currency: target_currency,
          source_currency: target_currency,
          conversion_needed: false,
          pricing_mode: :multi_currency,
          explicit_price: true
        }
      end

      # Fall back to product's default currency price
      base_price = find_base_price(product_currency, recurrence, is_rental)

      return nil if base_price.nil?

      {
        price_cents: base_price.price_cents,
        currency: product_currency,
        source_currency: product_currency,
        conversion_needed: target_currency != product_currency,
        pricing_mode: :multi_currency,
        explicit_price: false
      }
    end

    # Private: Find the base price for a given currency, recurrence, and rental status.
    #
    # currency   - The currency to look up.
    # recurrence - The recurrence period (optional).
    # is_rental  - Whether to find rental price.
    #
    # Returns Price object or nil.
    def find_base_price(currency, recurrence, is_rental)
      scoped_prices = is_rental ? alive_prices.is_rental : alive_prices.is_buy
      scoped_prices = scoped_prices.where(currency:)

      if recurrence.present?
        scoped_prices = scoped_prices.where(recurrence:)
      end

      scoped_prices.last
    end

    # Private: Adjust price value when transferring between currencies with different unit systems.
    # Handles conversion between single_unit currencies (like JPY) and cent-based currencies (like USD).
    #
    # price_cents      - The price value in source currency units.
    # source_currency  - The source currency code.
    # target_currency  - The target currency code.
    #
    # Returns Integer adjusted price value.
    def adjust_price_for_currency(price_cents, source_currency, target_currency)
      source_single_unit = currency_single_unit?(source_currency)
      target_single_unit = currency_single_unit?(target_currency)

      # If both currencies have the same unit system, no adjustment needed
      return price_cents if source_single_unit == target_single_unit

      if source_single_unit && !target_single_unit
        # Source is single unit (e.g., JPY), target uses cents (e.g., USD)
        # Convert: 100 JPY -> 10000 cents (multiply by 100)
        price_cents * 100
      else
        # Source uses cents (e.g., USD), target is single unit (e.g., JPY)
        # Convert: 10000 cents -> 100 JPY (divide by 100)
        (price_cents / 100.0).round
      end
    end
end
