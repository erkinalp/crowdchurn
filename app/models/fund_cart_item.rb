# frozen_string_literal: true

class FundCartItem < ApplicationRecord
  include ExternalId

  belongs_to :fund_cart
  belongs_to :product, class_name: "Link"
  belongs_to :purchase, optional: true

  validates :state, inclusion: { in: %w[pending purchased removed] }
  validate :product_not_from_same_seller
  validate :product_not_fund_cart
  validate :product_not_recurring_subscription
  validate :product_currency_matches_fund_cart

  scope :pending, -> { where(state: "pending") }
  scope :purchased, -> { where(state: "purchased") }

  def mark_purchased!(purchase)
    update!(state: "purchased", purchased_at: Time.current, purchase: purchase)
  end

  def mark_removed!
    update!(state: "removed")
  end

  private
    def product_not_from_same_seller
      return if fund_cart.blank? || product.blank?

      if product.user_id == fund_cart.user_id
        errors.add(:product, "must be from a different seller")
      end
    end

    def product_not_fund_cart
      return if product.blank?

      if product.native_type == "fund_cart"
        errors.add(:product, "cannot be a fund_cart product")
      end
    end

    def product_not_recurring_subscription
      return if product.blank?

      if product.is_recurring_billing?
        errors.add(:product, "cannot be a recurring subscription")
      end
    end

    def product_currency_matches_fund_cart
      return if fund_cart.blank? || product.blank?

      if product.price_currency_type != fund_cart.currency
        errors.add(:product, "must be priced in the same currency as the fund cart")
      end
    end
end
