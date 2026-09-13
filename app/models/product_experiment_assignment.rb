# frozen_string_literal: true

class ProductExperimentAssignment < ApplicationRecord
  belongs_to :product_experiment
  belongs_to :product_experiment_variant
  belongs_to :user, optional: true
  belongs_to :purchase, optional: true

  validates :assigned_at, presence: true

  def convert!(purchase)
    return if converted_at.present?

    update!(
      converted_at: Time.current,
      purchase: purchase
    )
    product_experiment_variant.increment!(:conversion_count)
  end
end
