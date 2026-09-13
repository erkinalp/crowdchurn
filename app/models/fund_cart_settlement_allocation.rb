# frozen_string_literal: true

class FundCartSettlementAllocation < ApplicationRecord
  belongs_to :fund_cart_settlement
  belongs_to :fund_cart_funding_lot
  alias_method :settlement, :fund_cart_settlement
  alias_method :funding_lot, :fund_cart_funding_lot

  validates :state, inclusion: { in: %w[reserved consumed cancelled reconciling reversed] }
  validates :amount_subunits, numericality: { only_integer: true, greater_than: 0 }
  validates :reversed_subunits, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: :amount_subunits }
end
