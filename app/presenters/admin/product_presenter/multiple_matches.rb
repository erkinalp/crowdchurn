# frozen_string_literal: true

class Admin::ProductPresenter::MultipleMatches
  attr_reader :product

  def initialize(product:)
    @product = product
  end

  def props
    {
      id: product.id,
      name: product.name,
      created_at: product.created_at,
      long_url: product.long_url,
      price_formatted: product.price_formatted,
      user: {
        external_id: product.user.external_id,
        name: product.user.name
      }
    }
  end
end
