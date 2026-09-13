# frozen_string_literal: true

FactoryBot.define do
  factory :variant_distribution_rule do
    association :post_variant
    association :base_variant, factory: :variant
    distribution_type { :percentage }
    distribution_value { 50 }

    trait :percentage do
      distribution_type { :percentage }
      distribution_value { 50 }
    end

    trait :count do
      distribution_type { :count }
      distribution_value { 100 }
    end

    trait :unlimited do
      distribution_type { :unlimited }
      distribution_value { nil }
    end
  end
end
