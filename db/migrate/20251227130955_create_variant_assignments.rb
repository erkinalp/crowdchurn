# frozen_string_literal: true

class CreateVariantAssignments < ActiveRecord::Migration[7.1]
  def change
    create_table :variant_assignments do |t|
      t.references :post_variant, null: false, foreign_key: true
      t.references :subscription, null: false, foreign_key: true
      t.datetime :assigned_at, null: false

      t.timestamps
    end

    add_index :variant_assignments, [:post_variant_id, :subscription_id],
              name: "index_variant_assignments_on_variant_and_subscription",
              unique: true
  end
end
