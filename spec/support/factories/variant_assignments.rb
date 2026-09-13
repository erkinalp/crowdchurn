# frozen_string_literal: true

FactoryBot.define do
  factory :variant_assignment do
    association :post_variant
    association :subscription
    assigned_at { Time.current }
  end
end
