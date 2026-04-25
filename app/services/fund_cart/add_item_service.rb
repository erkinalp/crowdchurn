# frozen_string_literal: true

class FundCart::AddItemService
  attr_reader :fund_cart, :product

  def initialize(fund_cart:, product:)
    @fund_cart = fund_cart
    @product = product
  end

  def perform
    item = fund_cart.fund_cart_items.build(product: product)

    if item.valid?
      item.save!
      [item, nil]
    else
      [nil, item.errors.full_messages.first]
    end
  end
end
