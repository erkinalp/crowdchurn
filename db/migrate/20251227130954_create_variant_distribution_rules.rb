# frozen_string_literal: true

class CreateVariantDistributionRules < ActiveRecord::Migration[7.1]
  def change
    create_table :variant_distribution_rules do |t|
      t.references :post_variant, null: false, foreign_key: true
      t.references :base_variant, null: false, foreign_key: true, type: :integer
      t.integer :distribution_type, null: false, default: 0
      t.integer :distribution_value

      t.timestamps
    end

    add_index :variant_distribution_rules, [:post_variant_id, :base_variant_id],
              name: "index_variant_distribution_rules_on_variant_and_tier",
              unique: true
  end
end
