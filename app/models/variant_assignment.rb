# frozen_string_literal: true

class VariantAssignment < ApplicationRecord
  belongs_to :post_variant
  belongs_to :subscription

  validates :assigned_at, presence: true
  validates :subscription_id, uniqueness: { scope: :post_variant_id, message: "has already been assigned to this variant" }

  before_validation :set_assigned_at, on: :create

  private
    def set_assigned_at
      self.assigned_at ||= Time.current
    end
end
