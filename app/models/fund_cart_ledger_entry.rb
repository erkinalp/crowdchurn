# frozen_string_literal: true

class FundCartLedgerEntry < ApplicationRecord
  belongs_to :fund_cart
  belongs_to :fund_cart_funding_lot, optional: true
  belongs_to :fund_cart_settlement, optional: true
  belongs_to :fund_cart_settlement_operation
  belongs_to :reversal_of, class_name: "FundCartLedgerEntry", optional: true
  belongs_to :user, optional: true
  belongs_to :merchant_account, optional: true

  validates :account, :currency, presence: true
  validates :amount_subunits, numericality: { only_integer: true, other_than: 0 }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "fund cart ledger is append-only" }

  def readonly?
    persisted?
  end
end
