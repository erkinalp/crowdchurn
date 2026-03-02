# frozen_string_literal: true

class CommunityProduct < ApplicationRecord
  belongs_to :community
  belongs_to :product, class_name: "Link"

  validates :community_id, uniqueness: { scope: :product_id }
  validate :community_and_product_belong_to_same_seller

  private
    def community_and_product_belong_to_same_seller
      return if community.blank? || product.blank?

      if community.seller_id != product.user_id
        errors.add(:base, "Community and product must belong to the same seller")
      end
    end
end
