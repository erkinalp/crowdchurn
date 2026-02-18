# frozen_string_literal: true

class AddBatchBillingToSubscriptions < ActiveRecord::Migration[7.1]
  def change
    add_column :subscriptions, :batch_entitled_at, :datetime, null: true
  end
end
