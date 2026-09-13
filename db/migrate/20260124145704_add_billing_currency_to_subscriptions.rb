# frozen_string_literal: true

class AddBillingCurrencyToSubscriptions < ActiveRecord::Migration[7.1]
  def change
    change_table :subscriptions, bulk: true do |t|
      t.string :billing_currency, default: "usd", null: false
      t.index :billing_currency
    end
  end
end
