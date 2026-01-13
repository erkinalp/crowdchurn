# frozen_string_literal: true

class AddShippingModeToLinks < ActiveRecord::Migration[7.1]
  def change
    # Add shipping_mode enum to links table
    # 0 = shipping_added (default): Shipping is calculated and added to the price
    # 1 = shipping_inclusive: Shipping is included in the product price (for gross pricing)
    # 2 = no_shipping: No shipping (digital products or free shipping)
    add_column :links, :shipping_mode, :integer, default: 0, null: false
  end
end
