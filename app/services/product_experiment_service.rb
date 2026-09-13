# frozen_string_literal: true

require "delegate"


class ProductExperimentService
  class ExperimentPrices < SimpleDelegator
    def initialize(prices, overrides)
      @overrides = overrides
      modified_prices = prices.map do |p|
        if p.recurrence.present? && (override = overrides[p.recurrence])
          p_clone = p.dup
          p_clone.price_cents = override
          # Ensure readonly to prevent accidental saves of ghost records
          p_clone.readonly!
          p_clone
        else
          p
        end
      end
      super(modified_prices)
    end

    def is_buy
      ExperimentPrices.new(select(&:is_buy?), @overrides)
    end

    def alive
      ExperimentPrices.new(select { |p| !p.deleted_at }, @overrides)
    end

    def where(opts)
      # Simple support for hash conditions used by Product::Prices
      filtered = select do |p|
        opts.all? do |k, v|
          # Handle simple equality or nil checks
          p.public_send(k) == v
        end
      end
      ExperimentPrices.new(filtered, @overrides)
    end

    # Support finding by non-standard means if necessary, but Array#find works for Enumerables
  end

  def initialize(product, user: nil, buyer_cookie: nil)
    @product = product
    @user = user
    @buyer_cookie = buyer_cookie
  end

  # Returns the product with overridden attributes if an experiment variant is assigned
  def call
    return @product unless @product.product_experiments.active.exists?

    # Prioritize logged-in user, then cookie
    experiment = @product.product_experiments.running.first
    return @product unless experiment

    variant = experiment.assign_variant(user: @user, buyer_cookie: @buyer_cookie)
    return @product unless variant

    apply_variant(variant)
  end

  private
    def apply_variant(variant)
      # Clone the product to avoid modifying the original and to prevent DB writes (safety)
      product_clone = @product.dup

      # Restore ID and persistence state so views/helpers treat it as the real record
      product_clone.id = @product.id
      product_clone.instance_variable_set(:@new_record, false)
      product_clone.instance_variable_set(:@destroyed, false)
      # Copy created_at/updated_at if needed, though usually not critical for display
      product_clone.created_at = @product.created_at
      product_clone.updated_at = @product.updated_at

      # Override Simple Attributes
      product_clone.description = variant.description_override if variant.description_override.present?

      # Override Price
      # We use singleton methods to bypass the complex logic in Product::Prices
      # that would otherwise fetch defaults from the DB.
      if variant.price_cents_override.present?
        override_price = variant.price_cents_override

        # Override low-level accessors
        # We accept *args and **kwargs to match signatures like default_price_cents(buyer_currency: nil) in Product::Prices
        product_clone.define_singleton_method(:price_cents) { |*args, **kwargs| override_price }
        product_clone.define_singleton_method(:buy_price_cents) { |*args, **kwargs| override_price }
        product_clone.define_singleton_method(:default_price_cents) { |*args, **kwargs| override_price }

        # Ensure displayed_price_cents (often used in views) matches
        product_clone.displayed_price_cents = override_price
      end

      # Override Recurrence Prices
      if variant.respond_to?(:recurrence_prices) && variant.recurrence_prices.present?
        # Capture current prices from original to avoid N+1 or reloading issues later
        # We assume @product.prices is accessible.
        current_prices = @product.prices.to_a

        # Define override for 'prices' association
        product_clone.define_singleton_method(:prices) do
          ExperimentPrices.new(current_prices, variant.recurrence_prices)
        end

        # Define override for 'alive_prices' association (often used in Product::Prices)
        product_clone.define_singleton_method(:alive_prices) do
          ExperimentPrices.new(current_prices.select { |p| !p.deleted_at }, variant.recurrence_prices)
        end
      end

      # Tag the clone
      product_clone.instance_variable_set(:@experiment_variant, variant)

      product_clone
    end
end
