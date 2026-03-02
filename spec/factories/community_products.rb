# frozen_string_literal: true

FactoryBot.define do
  factory :community_product do
    association :community
    association :product, factory: :product
  end
end
