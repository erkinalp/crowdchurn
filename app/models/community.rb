# frozen_string_literal: true

class Community < ApplicationRecord
  include Deletable
  include ExternalId

  belongs_to :seller, class_name: "User"
  belongs_to :resource, polymorphic: true

  has_many :community_chat_messages, dependent: :destroy
  has_many :last_read_community_chat_messages, dependent: :destroy
  has_many :community_chat_recaps, dependent: :destroy
  has_many :community_products, dependent: :destroy
  has_many :linked_products, through: :community_products, source: :product

  validates :seller_id, uniqueness: { scope: [:resource_id, :resource_type, :deleted_at] }

  def name
    read_attribute(:name).presence || resource.name
  end

  def thumbnail_url
    resource.for_email_thumbnail_url
  end

  def all_products
    product_ids = [resource_id]
    product_ids += community_products.pluck(:product_id)
    Link.where(id: product_ids.uniq)
  end

  def add_product!(product)
    raise ArgumentError, "Product must belong to the same seller" unless product.user_id == seller_id

    community_products.find_or_create_by!(product:)
  end

  def remove_product!(product)
    community_products.find_by!(product:).destroy!
  end
end
