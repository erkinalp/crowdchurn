# frozen_string_literal: true

class AddMultiCurrencyPricingSupport < ActiveRecord::Migration[7.1]
  def change
    # Add pricing_mode enum to links table
    # Values: 0 = legacy (single-currency with dynamic conversion, current behavior)
    #         1 = gross (same tax-inclusive value across currencies)
    #         2 = multi_currency (explicit prices per currency)
    add_column :links, :pricing_mode, :integer, default: 0, null: false

    # Add composite unique index on prices table for efficient lookups
    # and to ensure one price per product per currency per recurrence per rental status
    # Only applies to product prices (link_id is not null), not variant prices
    add_index :prices, [:link_id, :currency, :recurrence, :flags],
              unique: true,
              where: "link_id IS NOT NULL AND deleted_at IS NULL",
              name: "index_prices_on_link_currency_recurrence_flags_unique"
  end
end
