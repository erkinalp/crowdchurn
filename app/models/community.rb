# frozen_string_literal: true

class Community < ApplicationRecord
  include Deletable
  include ExternalId

  belongs_to :seller, class_name: "User"
  belongs_to :resource, polymorphic: true

  has_many :community_products, dependent: :destroy
  has_many :linked_products, through: :community_products, source: :product
  has_many :community_chat_messages, dependent: :destroy
  has_many :last_read_community_chat_messages, dependent: :destroy
  has_many :community_chat_recaps, dependent: :destroy

  validates :seller_id, uniqueness: { scope: [:resource_id, :resource_type, :deleted_at] }

  def name = self[:name].presence || resource.name

  def all_products
    Link.where(id: community_products.select(:product_id))
      .or(Link.where(id: resource_type == "Link" ? resource_id : nil))
  end

  def active_products
    other_shared_products = CommunityProduct.joins(:community).merge(Community.alive)
      .where.not(community_id: id).select(:product_id)

    all_products.alive.where(Link.community_chat_enabled_condition).where.not(id: other_shared_products)
  end

  def archive_if_unused!
    mark_deleted! unless active_products.exists?
  end

  def add_product!(product)
    raise ArgumentError, "Product must belong to the same seller" unless product.user_id == seller_id

    community_products.find_or_create_by!(product:)
  end

  def remove_product!(product)
    community_products.find_by!(product:).destroy!
  end

  def thumbnail_url
    resource.for_email_thumbnail_url
  end
end
