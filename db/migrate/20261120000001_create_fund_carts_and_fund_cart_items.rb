# frozen_string_literal: true

class CreateFundCartsAndFundCartItems < ActiveRecord::Migration[7.1]
  def change
    create_table :fund_carts do |t|
      t.bigint :link_id, null: false
      t.bigint :user_id, null: false
      t.bigint :balance_subunits, default: 0, null: false
      t.string :currency, null: false
      t.timestamps

      t.index :link_id, unique: true
      t.index :user_id
    end

    create_table :fund_cart_items do |t|
      t.bigint :fund_cart_id, null: false
      t.bigint :product_id, null: false
      t.string :state, default: "pending", null: false
      t.datetime :purchased_at
      t.bigint :purchase_id
      t.timestamps

      t.index :fund_cart_id
      t.index :product_id
      t.index :state
      t.index :purchase_id
    end
  end
end
