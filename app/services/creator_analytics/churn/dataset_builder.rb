# frozen_string_literal: true

class CreatorAnalytics::Churn::DatasetBuilder
  attr_reader :product_scope, :date_window, :churn_events, :new_subscriptions, :initial_active_counts

  def initialize(product_scope:, date_window:, churn_events:, new_subscriptions:, initial_active_counts:)
    @product_scope = product_scope
    @date_window = date_window
    @churn_events = churn_events
    @new_subscriptions = new_subscriptions
    @initial_active_counts = initial_active_counts
  end

  # Sample output:
  # {
  #   metadata: { timezone: "-07:00", products: [{ external_id: "123", name: "Alpha" }] },
  #   data: { daily: { "2024-05-01" => { total: { churn_rate: 1.0 } } }, monthly: {...} }
  # }
  def build
    daily_data, monthly_inputs = build_daily_data

    {
      metadata: metadata_payload,
      data: {
        daily: daily_data,
        monthly: build_monthly_data(monthly_inputs)
      }
    }
  end

  private
    def metadata_payload
      {
        start_date: date_window.start_date.to_s,
        end_date: date_window.end_date.to_s,
        timezone: date_window.timezone_offset,
        products: product_infos.values.map do |info|
          {
            external_id: info[:external_id],
            permalink: info[:permalink],
            name: info[:name]
          }
        end
      }
    end

    def product_infos
      @product_infos ||= product_scope.product_map
    end

    def build_daily_data
      running_active = Hash.new(0).merge(initial_active_counts)
      monthly_inputs = Hash.new do |hash, month_key|
        hash[month_key] = {
          by_product: Hash.new do |inner_hash, permalink|
            inner_hash[permalink] = { churned: 0, revenue: 0, active_start: nil, new_subscriptions: 0 }
          end,
          total: { churned: 0, revenue: 0, active_start: 0, new_subscriptions: 0 }
        }
      end

      daily_results = {}

      date_window.daily_dates.each do |date|
        day_key = date.to_s
        month_key = Date.new(date.year, date.month, 1).to_s
        totals_tracker = { churned: 0, revenue: 0, denominator: 0 }

        daily_results[day_key] = { by_product: {}, total: zero_stat_hash }

        product_infos.each do |product_id, info|
          new_count = new_subscriptions.fetch([product_id, date], 0)
          churn_entry = churn_events.fetch([product_id, date], { churned_count: 0, revenue_lost_cents: 0 })
          churn_count = churn_entry[:churned_count]
          revenue = churn_entry[:revenue_lost_cents]

          active_base = running_active.fetch(product_id, 0)
          denominator = active_base + new_count
          churn_rate = denominator.positive? ? ((churn_count.to_f / denominator) * 100).round(2) : 0.0

          daily_results[day_key][:by_product][info[:permalink]] = {
            churn_rate: churn_rate,
            churned_customers_count: churn_count,
            revenue_lost_cents: revenue
          }

          monthly_product_entry = monthly_inputs[month_key][:by_product][info[:permalink]]
          if monthly_product_entry[:active_start].nil?
            monthly_product_entry[:active_start] = active_base
            monthly_inputs[month_key][:total][:active_start] += active_base
          end

          monthly_product_entry[:new_subscriptions] += new_count
          monthly_inputs[month_key][:total][:new_subscriptions] += new_count

          totals_tracker[:churned] += churn_count
          totals_tracker[:revenue] += revenue
          totals_tracker[:denominator] += denominator

          monthly_product_entry[:churned] += churn_count
          monthly_product_entry[:revenue] += revenue

          running_active[product_id] = [active_base + new_count - churn_count, 0].max
        end

        denom = totals_tracker[:denominator]
        total_rate = denom.positive? ? ((totals_tracker[:churned].to_f / denom) * 100).round(2) : 0.0
        daily_results[day_key][:total] = {
          churn_rate: total_rate,
          churned_customers_count: totals_tracker[:churned],
          revenue_lost_cents: totals_tracker[:revenue]
        }

        monthly_inputs[month_key][:total][:churned] += totals_tracker[:churned]
        monthly_inputs[month_key][:total][:revenue] += totals_tracker[:revenue]
      end

      [daily_results, monthly_inputs]
    end

    def build_monthly_data(monthly_inputs)
      date_window.monthly_dates.each_with_object({}) do |month_date, result|
        month_key = month_date.to_s
        month_entry = monthly_inputs[month_key]
        month_entry ||= {
          by_product: Hash.new do |inner_hash, permalink|
            inner_hash[permalink] = { churned: 0, revenue: 0, active_start: nil, new_subscriptions: 0 }
          end,
          total: { churned: 0, revenue: 0, active_start: 0, new_subscriptions: 0 }
        }
        result[month_key] = {
          by_product: build_monthly_products(month_entry[:by_product]),
          total: build_monthly_total(month_entry[:total])
        }
      end
    end

    def build_monthly_products(monthly_product_data)
      product_infos.values.each_with_object({}) do |info, result|
        per_product = monthly_product_data[info[:permalink]]
        churned = per_product[:churned]
        revenue = per_product[:revenue]
        active_start = per_product[:active_start] || 0
        denominator = active_start + per_product[:new_subscriptions]
        rate = denominator.positive? ? ((churned.to_f / denominator) * 100).round(2) : 0.0

        result[info[:permalink]] = {
          churn_rate: rate,
          churned_customers_count: churned,
          revenue_lost_cents: revenue
        }
      end
    end

    def build_monthly_total(total_data)
      denominator = total_data[:active_start] + total_data[:new_subscriptions]
      rate = denominator.positive? ? ((total_data[:churned].to_f / denominator) * 100).round(2) : 0.0
      {
        churn_rate: rate,
        churned_customers_count: total_data[:churned],
        revenue_lost_cents: total_data[:revenue]
      }
    end

    def zero_stat_hash
      { churn_rate: 0.0, churned_customers_count: 0, revenue_lost_cents: 0 }
    end
end
