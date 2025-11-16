# frozen_string_literal: true

# Usage:
#   rails runner db/seeds/churn_demo.rb
# or
#   CHURN_SELLER_EMAIL=creator@example.com rails runner db/seeds/churn_demo.rb
#
# The script creates recurring products, buyers, subscriptions, and purchases for churn analytics.

if Rails.env.production?
  puts "Skipping churn demo seeds in production"
  exit 0
end

def prompt(message)
  print(message)
  STDOUT.flush
  STDIN.gets&.strip
end

def log(message)
  puts(message)
end

seller_email = ENV["CHURN_SELLER_EMAIL"]
seller_email = prompt("Enter seller email: ") if seller_email.blank?

if seller_email.blank?
  warn "Seller email is required. Aborting."
  exit 1
end

demo_data = CreatorAnalytics::Churn::DemoData.new(seller_email:, logger: ->(msg) { log(msg) })

if ENV["CHURN_PURGE"] == "1"
  demo_data.purge
else
  demo_data.seed
end
