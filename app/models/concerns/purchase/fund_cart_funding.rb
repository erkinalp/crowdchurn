# frozen_string_literal: true

module Purchase::FundCartFunding
  extend ActiveSupport::Concern

  included do
    has_one :fund_cart_funding_lot, foreign_key: :source_purchase_id, dependent: :restrict_with_exception
    has_one :fund_cart_settlement, dependent: :restrict_with_exception
    attr_accessor :fund_cart_pricing, :fund_cart_refund_pending
    validate :fund_cart_contribution_route_eligible
  end

  def fund_cart_contribution?
    link&.native_type == Link::NATIVE_TYPE_FUND_CART
  end

  def has_fund_cart_settlement?
    persisted? && ApplicationRecord.connected_to(role: :writing) { FundCartSettlement.exists?(purchase_id: id) }
  end

  def funded_by_fund_cart?
    return false unless persisted?
    ApplicationRecord.connected_to(role: :writing) do
      FundCartSettlement.find_by(purchase_id: id)&.valid_receipt_for?(self) || false
    end
  end

  def ensure_fund_cart_funding_eligible!(resolved_merchant: nil, processor_currency: nil)
    raise FundCart::SettlementError, "funded_destination_cannot_charge" if has_fund_cart_settlement?
    return unless fund_cart_contribution? && !is_test_purchase? && price_cents.to_i.positive?
    FundCart::Eligibility.contribution(purchase: self, resolved_merchant:, processor_currency:).ensure_supported!
  end

  private
    def fund_cart_contribution_route_eligible
      return unless fund_cart_contribution? && in_progress? && merchant_account.present? && !is_test_purchase?
      return unless price_cents.to_i.positive?
      result = FundCart::Eligibility.contribution(purchase: self)
      errors.add(:base, "Fund cart funding unavailable: #{result.code}") unless result.supported?
    end

    def calculate_fund_cart_fees
      self.fee_cents = 0
      return if price_cents.to_i.zero?
      calculate_custom_fee_per_thousand
      # Internal settlement retains the platform fee, but incurs no second acquiring charge.
      rate = custom_fee_per_thousand.presence || operator_flat_fee_per_thousand
      self.fee_cents = (Rational(price_cents * rate, 1000)).round + Purchase::OPERATOR_FIXED_FEE_CENTS
      self.affiliate_credit_cents = determine_affiliate_balance_cents
    end
end
