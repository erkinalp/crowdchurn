# frozen_string_literal: true

class FundCart::AllocateFundsService
  attr_reader :fund_cart

  def initialize(fund_cart:)
    @fund_cart = fund_cart
  end

  # Caller is responsible for wrapping this call in `fund_cart.with_lock` so
  # balance updates and item state transitions stay consistent under concurrent
  # contributions. See FundCart::ContributeService for the canonical caller.
  def perform
    pending_items = fund_cart.pending_items

    pending_items.each do |item|
      product = item.product
      total_cost = product.price_cents

      next if total_cost > fund_cart.balance_subunits
      next if total_cost <= 0

      purchase = create_purchase_for_item(product)
      next if purchase.blank?

      fund_cart.update!(balance_subunits: fund_cart.balance_subunits - total_cost)
      item.mark_purchased!(purchase)
    end
  end

  private
    def create_purchase_for_item(product)
      buyer = fund_cart.user

      purchase = product.sales.build(
        email: buyer.email,
        seller: product.user,
        purchaser: buyer,
        perceived_price_cents: product.price_cents,
        displayed_price_currency_type: product.price_currency_type,
        was_product_recommended: false,
      )

      purchase.prepare_for_charge!
      purchase.update_balance_and_mark_successful!

      if purchase.errors.present?
        Rails.logger.error("FundCart::AllocateFundsService: Failed to create purchase for product #{product.id}: #{purchase.errors.full_messages.join(', ')}")
        return nil
      end

      purchase
    rescue StandardError => e
      Rails.logger.error("FundCart::AllocateFundsService: Error creating purchase for product #{product.id}: #{e.message}")
      nil
    end
end
