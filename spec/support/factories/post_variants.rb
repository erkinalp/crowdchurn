# frozen_string_literal: true

FactoryBot.define do
  factory :post_variant do
    association :installment
    name { Faker::Lorem.words(number: 2).join(" ") }
    message { Faker::Lorem.paragraph }
    is_control { false }

    trait :control do
      is_control { true }
    end
  end
end
