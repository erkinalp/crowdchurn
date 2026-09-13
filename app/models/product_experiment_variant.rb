# frozen_string_literal: true

class ProductExperimentVariant < ApplicationRecord
  belongs_to :product_experiment
  has_many :product_experiment_assignments, dependent: :destroy

  validates :name, presence: true
  validates :weight, numericality: { greater_than_or_equal_to: 0 }
  validate :recurrence_prices_format, if: -> { recurrence_prices.present? }

  def recurrence_prices_format
    unless recurrence_prices.is_a?(Hash)
      errors.add(:recurrence_prices, "must be a hash")
      return
    end

    recurrence_prices.each do |key, value|
      unless key.in?(BasePrice::Recurrence::ALLOWED_RECURRENCES)
        errors.add(:recurrence_prices, "contains invalid recurrence key: #{key}")
      end
      unless value.is_a?(Integer) && value >= 0
        errors.add(:recurrence_prices, "contains invalid price value for #{key}: must be a non-negative integer")
      end
    end
  end

  def conversion_rate
    return 0.0 if traffic_count.zero?
    (conversion_count.to_f / traffic_count * 100).round(2)
  end
end
