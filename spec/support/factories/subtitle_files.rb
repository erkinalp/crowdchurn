# frozen_string_literal: true

FactoryBot.define do
  factory :subtitle_file do
    product_file
    url { "#{S3_BASE_URL}/#{SecureRandom.hex}.srt" }
    language { "English" }
  end
end
