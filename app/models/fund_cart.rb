# frozen_string_literal: true

class FundCart < ApplicationRecord
  include NanoExternalId

  belongs_to :link
  belongs_to :user
  has_many :fund_cart_items, dependent: :destroy

  validates :currency, presence: true
  validates :balance_subunits, numericality: { greater_than_or_equal_to: 0 }
  validate :currency_matches_link

  ITEM_TYPE_PRIORITY = {
    "digital" => 0,
    "course" => 0,
    "ebook" => 0,
    "physical" => 1,
    "print_book" => 1,
    "food" => 1,
    "bread" => 1,
    "literal_coffee" => 1,
    "bundle" => 2,
  }.freeze

  def pending_items
    fund_cart_items
      .where(state: "pending")
      .includes(:product)
      .sort_by { |item| [-item.product.price_cents, type_priority(item.product)] }
  end

  private
    def currency_matches_link
      return if link.blank?

      if currency != link.price_currency_type
        errors.add(:currency, "must match the product's currency")
      end
    end

    def type_priority(product)
      ITEM_TYPE_PRIORITY.fetch(product.native_type, 0)
    end
end
