# frozen_string_literal: true

class VariantAssignment < ApplicationRecord
  include ExternalId

  belongs_to :post_variant
  belongs_to :subscription

  validates :assigned_at, presence: true
  validates :subscription_id, uniqueness: { scope: :post_variant_id, message: "has already been assigned to this variant" }

  before_validation :set_assigned_at, on: :create

  def as_json(_options = {})
    {
      "id" => external_id,
      "post_variant_id" => post_variant.external_id,
      "subscription_id" => subscription.external_id,
      "assigned_at" => assigned_at
    }
  end

  private
    def set_assigned_at
      self.assigned_at ||= Time.current
    end
end
