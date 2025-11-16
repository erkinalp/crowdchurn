# frozen_string_literal: true

class CreatorAnalytics::Churn
  InvalidDateRange = Class.new(StandardError)

  attr_reader :seller

  def initialize(seller:)
    @seller = seller
  end

  def subscription_products
    product_scope.subscription_products
  end


  # Sample output:
  # {
  #   metadata: {
  #     start_date: "2025-10-16",
  #     end_date: "2025-11-16",
  #     timezone: "+00:00",
  #     products: [
  #       { external_id: "FxlavpQXIwDwiwB3Q4nWrw==", permalink: "gm", name: "Enterprise Membership" },
  #       { external_id: "euRm4g7swijZgqyrIhRfiQ==", permalink: "vd", name: "Premium Membership "},
  #       { external_id: "r4pQ8_yK3PeMDO09QAVajQ==", permalink: "tmt", name: "Beta Membership" },
  #       { external_id: "FeGnju-VsIHoeR_1dTrxAg==", permalink: "zf", name: "Alpha Membership" }
  #     ]
  #   },
  #   data: {
  #     daily: {
  #       "2025-10-16" => {
  #         by_product: {
  #           "gm" => { churn_rate: 0.0, churned_customers_count: 0, revenue_lost_cents: 0 },
  #           "vd" => { churn_rate: 0.21, churned_customers_count: 1, revenue_lost_cents: 19900 },
  #           "tmt" => { churn_rate: 0.22, churned_customers_count: 1, revenue_lost_cents: 1500 },
  #           "zf" => { churn_rate: 0.52, churned_customers_count: 4, revenue_lost_cents: 4000 }
  #         },
  #         total: {
  #           churn_rate: 0.29,
  #           churned_customers_count: 6,
  #           revenue_lost_cents: 25400
  #         }
  #       },
  #       { ... }
  #     },
  #     monthly: {
  #       "2025-10-01" => {
  #         by_product: {
  #           "gm" => { churn_rate: 0.79, churned_customers_count: 3, revenue_lost_cents: 750000 },
  #           "vd" => { churn_rate: 1.24, churned_customers_count: 6, revenue_lost_cents: 119400 },
  #           "tmt" => { churn_rate: 3.13, churned_customers_count: 15, revenue_lost_cents: 22500 },
  #           "zf" => { churn_rate: 3.03, churned_customers_count: 24, revenue_lost_cents: 24000 }
  #         },
  #         total: { churn_rate: 2.25, churned_customers_count: 48, revenue_lost_cents: 915900 }
  #       },
  #       { ... }
  #     }
  #   }
  # }
  def generate_data(start_date:, end_date:)
    date_window = CreatorAnalytics::Churn::DateWindow.new(
      seller:,
      product_scope:,
      start_date:,
      end_date:
    )

    if cacheable_range?(date_window)
      cached = read_cached_payload(date_window)
      return cached if cached
    end

    payload = build_payload(date_window)
    write_cached_payload(date_window, payload) if cacheable_range?(date_window)
    payload
  end

  private

  def product_scope
    @product_scope ||= CreatorAnalytics::Churn::ProductScope.new(seller:)
  end

  def build_payload(date_window)
    fetcher = CreatorAnalytics::Churn::ElasticsearchFetcher.new(
      seller:,
      products: subscription_products,
      date_window:
    )

    CreatorAnalytics::Churn::DatasetBuilder.new(
      product_scope:,
      date_window:,
      churn_events: fetcher.churn_events,
      new_subscriptions: fetcher.new_subscriptions,
      initial_active_counts: fetcher.initial_active_counts
    ).build
  end

  def use_cache?
    @use_cache ||= LargeSeller.where(user: seller).exists?
  end

  def cacheable_range?(date_window)
    return false unless use_cache?
    date_window.end_date <= cache_cutoff_date
  end

  def cache_cutoff_date
    @cache_cutoff_date ||= (Time.zone.now.in_time_zone(seller.timezone).to_date - 2.days)
  end

  def read_cached_payload(date_window)
    record = ComputedSalesAnalyticsDay.find_by(key: cache_key_for(date_window))
    return unless record
    JSON.parse(record.data).deep_symbolize_keys
  end

  def write_cached_payload(date_window, payload)
    ComputedSalesAnalyticsDay.upsert_data_from_key(cache_key_for(date_window), payload)
  end

  def cache_key_for(date_window)
    version = $redis.get(RedisKey.seller_analytics_cache_version) || 0
    [
      "creator_analytics_churn",
      "v#{version}",
      "seller_#{seller.id}",
      seller.timezone,
      date_window.start_date,
      date_window.end_date
    ].join(":")
  end
end
