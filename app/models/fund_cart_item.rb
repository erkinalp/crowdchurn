# frozen_string_literal: true

class FundCartItem < ApplicationRecord
  include NanoExternalId

  belongs_to :fund_cart
  belongs_to :product, class_name: "Link"
  belongs_to :purchase, optional: true
  has_many :settlements, class_name: "FundCartSettlement", dependent: :restrict_with_exception

  before_destroy :prevent_reserved_item_destruction
  validate :prevent_reserved_item_mutation, on: :update

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
    fund_cart.with_lock do
      lock!
      raise FundCart::SettlementError, "item_has_active_settlement" if active_settlement?
      update!(state: "removed")
    end
  end

  def active_settlement?
    settlements.where.not(active_item_id: nil).exists?
  end

  def removal_blocking_reason
    "item_has_active_settlement" if active_settlement?
  end

  private
    def prevent_reserved_item_destruction
      return unless active_settlement?
      errors.add(:base, "item_has_active_settlement")
      throw :abort
    end

    def prevent_reserved_item_mutation
      return unless (state_changed? && state == "removed") || product_id_changed? || purchase_options_changed?
      errors.add(:base, "item_has_active_settlement") if active_settlement?
    end

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
