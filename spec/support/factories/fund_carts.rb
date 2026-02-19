# frozen_string_literal: true

FactoryBot.define do
  factory :fund_cart_product, parent: :product do
    user { create(:user, :eligible_for_service_products) }
    native_type { Link::NATIVE_TYPE_FUND_CART }
  end

  factory :fund_cart do
    association :link, factory: :fund_cart_product
    user { link.user }
    balance_cents { 0 }
    currency { "usd" }
  end

  factory :fund_cart_item do
    association :fund_cart
    association :product, factory: :product
    state { "pending" }
  end
end
