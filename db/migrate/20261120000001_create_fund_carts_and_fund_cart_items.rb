# frozen_string_literal: true

class CreateFundCartsAndFundCartItems < ActiveRecord::Migration[7.1]
  def change
    create_table :fund_carts do |t|
      t.bigint :link_id, null: false
      t.bigint :user_id, null: false
      t.bigint :balance_cents, default: 0, null: false
      t.string :currency, null: false
      t.timestamps
    end

    add_index :fund_carts, :link_id, unique: true
    add_index :fund_carts, :user_id

    create_table :fund_cart_items do |t|
      t.bigint :fund_cart_id, null: false
      t.bigint :product_id, null: false
      t.string :state, default: "pending", null: false
      t.datetime :purchased_at
      t.bigint :purchase_id
      t.timestamps
    end

    add_index :fund_cart_items, :fund_cart_id
    add_index :fund_cart_items, :product_id
    add_index :fund_cart_items, :state
    add_index :fund_cart_items, :purchase_id
  end
end
