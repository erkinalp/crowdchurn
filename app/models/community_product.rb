# frozen_string_literal: true

class CommunityProduct < ApplicationRecord
  belongs_to :community
  belongs_to :product, class_name: "Link"

  validates :community_id, uniqueness: { scope: :product_id }
  validate :community_and_product_belong_to_same_seller

  before_create :lock_active_community
  before_destroy -> { community.lock! }

  private
    def lock_active_community
      community.lock!
      raise ActiveRecord::RecordNotFound, "Community is archived" unless community.alive?
    end

    def community_and_product_belong_to_same_seller
      return if community.blank? || product.blank?

      if community.seller_id != product.user_id
        errors.add(:base, "Community and product must belong to the same seller")
      end
    end
end
