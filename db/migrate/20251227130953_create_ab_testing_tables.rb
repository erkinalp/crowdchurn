# frozen_string_literal: true

class CreateAbTestingTables < ActiveRecord::Migration[7.1]
  def change
    # Create post_variants table for A/B testing content and price variants
    create_table :post_variants do |t|
      t.references :installment, null: false, foreign_key: true, type: :integer
      t.string :name, null: false
      t.text :message, size: :long, null: false
      t.boolean :is_control, default: false, null: false
      t.integer :price_cents, null: true

      t.timestamps
    end

    add_index :post_variants, [:installment_id, :is_control], name: "index_post_variants_on_installment_id_and_is_control"

    # Create variant_distribution_rules table for controlling variant distribution
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

    # Create variant_assignments table for tracking buyer variant assignments
    create_table :variant_assignments do |t|
      t.references :post_variant, null: false, foreign_key: true
      t.references :subscription, null: true, foreign_key: true
      t.datetime :assigned_at, null: false
      t.bigint :user_id, null: true
      t.string :buyer_cookie, null: true

      t.timestamps

      t.index [:post_variant_id, :subscription_id],
              name: "index_variant_assignments_on_variant_and_subscription",
              unique: true
      t.index [:user_id, :post_variant_id],
              unique: true,
              where: "user_id IS NOT NULL",
              name: "index_variant_assignments_on_user_and_post_variant"
      t.index [:buyer_cookie, :post_variant_id],
              unique: true,
              where: "buyer_cookie IS NOT NULL",
              name: "index_variant_assignments_on_buyer_cookie_and_post_variant"
    end

    # Add post_variant reference to comments for variant-scoped comments
    add_reference :comments, :post_variant, null: true, foreign_key: true
    add_index :comments, [:commentable_id, :commentable_type, :post_variant_id],
              name: "index_comments_on_commentable_and_post_variant"
  end
end
