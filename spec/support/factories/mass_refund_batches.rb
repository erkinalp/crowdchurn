# frozen_string_literal: true

FactoryBot.define do
  factory :mass_refund_batch do
    association :product, factory: :product
    association :admin_user
    purchase_ids { [1, 2] }
    status { :pending }
    refunded_count { 0 }
    blocked_count { 0 }
    failed_count { 0 }
    errors_by_purchase_id { {} }
  end
end
