# frozen_string_literal: true

class ProductExperiment < ApplicationRecord
  belongs_to :product, class_name: "Link"
  has_many :product_experiment_variants, dependent: :destroy
  has_many :product_experiment_assignments, dependent: :destroy

  validates :name, presence: true
  validates :status, inclusion: { in: %w[active paused completed] }

  scope :active, -> { where(status: "active") }
  scope :running, -> { active.where("started_at <= ? AND (ended_at IS NULL OR ended_at >= ?)", Time.current, Time.current) }

  def total_traffic
    product_experiment_variants.sum(:traffic_count)
  end

  def total_conversions
    product_experiment_variants.sum(:conversion_count)
  end

  # Select a variant for a user/visitor
  def assign_variant(user: nil, buyer_cookie: nil)
    # 1. Check for existing assignment
    assignment = product_experiment_assignments.where(user:)
                                               .or(product_experiment_assignments.where(buyer_cookie:))
                                               .first
    return assignment.product_experiment_variant if assignment.present?

    # 2. Select new variant based on weights
    selected_variant = select_random_variant
    return nil unless selected_variant

    # 3. Create assignment
    ProductExperimentAssignment.create!(
      product_experiment: self,
      product_experiment_variant: selected_variant,
      user:,
      buyer_cookie:,
      assigned_at: Time.current
    )

    # 4. Increment traffic stats (async in real app, sync here for simplicity)
    selected_variant.increment!(:traffic_count)

    selected_variant
  end

  private
    def select_random_variant
      total_weight = product_experiment_variants.sum(:weight)
      return product_experiment_variants.first if total_weight.zero?

      random_point = rand(1..total_weight)
      current_weight = 0
      product_experiment_variants.each do |variant|
        current_weight += variant.weight
        return variant if random_point <= current_weight
      end
      product_experiment_variants.last
    end
end
