# frozen_string_literal: true

class FundCartSettlement < ApplicationRecord
  include NanoExternalId

  ACTIVE_STATES = %w[reserved processing reconciling settled].freeze
  belongs_to :fund_cart
  belongs_to :fund_cart_item
  belongs_to :purchase
  belongs_to :beneficiary, class_name: "User"
  belongs_to :seller, class_name: "User"
  belongs_to :destination_merchant_account, class_name: "MerchantAccount"
  has_many :allocations, class_name: "FundCartSettlementAllocation", dependent: :restrict_with_exception
  has_many :operations, class_name: "FundCartSettlementOperation", dependent: :restrict_with_exception
  has_many :ledger_entries, class_name: "FundCartLedgerEntry", dependent: :restrict_with_exception

  validates :state, inclusion: { in: %w[reserved processing settled failed cancelled reconciling reversed] }
  validates :operation_key, presence: true, uniqueness: true
  validates :amount_subunits, numericality: { only_integer: true, greater_than: 0 }

  # Read from primary and durable associations, never an unsaved association supplied by a caller.
  def valid_receipt_for?(candidate)
    return false unless state.in?(%w[settled reversed]) && settled_at.present? && receipt.present?
    return false unless candidate.persisted? && purchase_id == candidate.id && beneficiary_id == candidate.purchaser_id && seller_id == candidate.seller_id
    return false unless fund_cart.user_id == beneficiary_id && fund_cart_item.product_id == candidate.link_id && fund_cart_item.purchase_id == candidate.id
    return false unless destination_merchant_account_id == candidate.merchant_account_id && candidate.stripe_transaction_id.blank? && candidate.charge.blank? && candidate.charge_processor_id.blank?
    return false unless amount_subunits == candidate.total_transaction_cents && currency == Currency.base && currency == candidate.displayed_price_currency_type.to_s
    snapshot = FundCart::QuoteService.snapshot(candidate, item: fund_cart_item)
    monetary_keys = %w[product_id seller_id beneficiary_id merchant_account_id currency currency_exponent listed_currency listed_subunits rate_converted_to_base amount_subunits price_subunits seller_tax_subunits platform_tax_subunits shipping_subunits fee_subunits affiliate_subunits quantity variant_ids address]
    return false unless quote_snapshot.slice(*monetary_keys) == snapshot.slice(*monetary_keys)
    return false unless receipt["operation_key"] == operation_key && receipt["amount_subunits"] == amount_subunits.to_i && receipt["currency"] == currency && receipt["custody_key"] == custody_key
    allocation_rows = allocations.includes(:fund_cart_funding_lot).to_a
    return false if allocation_rows.empty? || allocation_rows.sum(&:amount_subunits) != amount_subunits
    return false unless allocation_rows.all? { |allocation| allocation.state.in?(%w[consumed reversed]) && allocation.funding_lot.backed? && allocation.funding_lot.custody_key == custody_key && allocation.funding_lot.currency == currency }
    operation = operations.find_by(operation_key: "settle:#{operation_key}", state: "completed")
    return false unless operation
    transaction = candidate.balance_transactions.find_by(id: receipt["seller_balance_transaction_id"], user_id: seller_id, merchant_account_id: destination_merchant_account_id)
    return false unless transaction && transaction.balance_id == candidate.purchase_success_balance_id &&
      transaction.issued_amount_currency == currency && transaction.holding_amount_currency == currency &&
      transaction.issued_amount_gross_cents == amount_subunits && transaction.holding_amount_gross_cents == amount_subunits &&
      transaction.issued_amount_net_cents == candidate.payment_cents - candidate.affiliate_credit_cents &&
      transaction.holding_amount_net_cents == transaction.issued_amount_net_cents
    entries = operation.ledger_entries
    entries.where(account: "reserved").sum(:amount_subunits) == -amount_subunits &&
      entries.sum(:amount_subunits).zero? &&
      entries.where(account: %w[seller_payable platform_fee platform_tax affiliate_payable]).sum(:amount_subunits) == amount_subunits
  end
end
