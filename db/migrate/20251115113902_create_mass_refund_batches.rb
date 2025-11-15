# frozen_string_literal: true

class CreateMassRefundBatches < ActiveRecord::Migration[7.1]
  def change
    create_table :mass_refund_batches do |t|
      t.references :product, null: false, foreign_key: { to_table: :links }
      t.references :admin_user, null: false, foreign_key: { to_table: :users }
      t.json :purchase_ids, null: false
      t.integer :status, null: false, default: 0
      t.integer :refunded_count, null: false, default: 0
      t.integer :blocked_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.json :errors_by_purchase_id, null: false
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :mass_refund_batches, [:product_id, :created_at]
    add_index :mass_refund_batches, :status
  end
end
