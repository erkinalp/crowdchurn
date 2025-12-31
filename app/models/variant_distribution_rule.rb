# frozen_string_literal: true

class VariantDistributionRule < ApplicationRecord
  belongs_to :post_variant
  belongs_to :base_variant

  enum :distribution_type, { percentage: 0, count: 1, unlimited: 2 }

  validates :distribution_type, presence: true
  validates :distribution_value, presence: true, if: -> { percentage? || count? }
  validates :distribution_value, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, if: :percentage?
  validates :distribution_value, numericality: { greater_than: 0 }, if: :count?

  def slots_available?(current_assignment_count)
    return true if unlimited?
    return true if percentage?

    current_assignment_count < distribution_value
  end
end
