# frozen_string_literal: true

class FundCartFundingLot < ApplicationRecord
  include NanoExternalId

  belongs_to :fund_cart
  belongs_to :source_purchase, class_name: "Purchase"
  belongs_to :beneficiary, class_name: "User"
  belongs_to :source_merchant_account, class_name: "MerchantAccount"
  has_many :allocations, class_name: "FundCartSettlementAllocation", dependent: :restrict_with_exception
  has_many :ledger_entries, dependent: :restrict_with_exception, class_name: "FundCartLedgerEntry"
  has_many :operations, class_name: "FundCartSettlementOperation", dependent: :restrict_with_exception

  validates :source_purchase_id, uniqueness: true
  validates :state, inclusion: { in: %w[pending available frozen reconciling reversed] }
  validates :currency, :canonical_currency, :custody_key, :processor, presence: true
  validates :net_subunits, :available_subunits, :reserved_subunits, :spent_subunits, :reversed_subunits, :debt_subunits,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :backing_conservation

  def backed?
    confirmed_at.present? && restricted_at.present? && reserve_reference.present? &&
      confirmation_evidence.present? && confirmation_evidence["custody_key"] == custody_key &&
      confirmation_evidence["payment_id"] == source_payment_id && confirmation_evidence["balance_transaction_id"] == source_balance_transaction_id &&
      confirmation_evidence["currency"] == currency && confirmation_evidence["currency_exponent"] == currency_exponent &&
      confirmation_evidence["source_net_subunits"] == net_subunits
  end

  def spendable?
    state == "available" && debt_subunits.zero? && backed? && confirmation_evidence["availability_verified"] != false &&
      available_at.present? && available_at <= Time.current && fund_cart.ledger_active? &&
      source_purchase.successful? && !source_purchase.stripe_refunded? && !source_purchase.chargedback_not_reversed? &&
      (!source_purchase.stripe_partially_refunded? || source_purchase.refunds.effective.exists?) &&
      source_purchase.refunds.effective.where.not(id: operations.where(kind: "source_refund", state: "completed").where.not(refund_id: nil).select(:refund_id)).none? &&
      source_purchase.purchase_success_balance_id.nil? && !source_purchase.balance_transactions.where(user_id: beneficiary_id).exists?
  end

  def authorized_available_subunits
    return 0 unless spendable?
    [available_subunits.to_i, ledger_entries.where(account: "available", currency:).sum(:amount_subunits).to_i].min.clamp(0, net_subunits.to_i)
  end

  private
    def backing_conservation
      return unless confirmed_at?
      if available_subunits + reserved_subunits + spent_subunits + reversed_subunits != net_subunits + debt_subunits
        errors.add(:base, "funding lot does not conserve its backing")
      end
      errors.add(:base, "funding lot currency differs from cart") if currency != fund_cart.currency
    end
end
