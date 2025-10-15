# frozen_string_literal: true

FactoryBot.define do
  factory :stamped_pdf do
    url_redirect
    product_file
    url { "#{S3_BASE_URL}/attachment/manual_stamped.pdf" }
  end
end
