# frozen_string_literal: true

class CreateProductExperiments < ActiveRecord::Migration[7.1]
  def change
    create_table :product_experiments do |t|
      t.references :product, null: false, foreign_key: { to_table: :links } # Link is the product model name
      t.string :name, null: false
      t.string :status, null: false, default: "active"
      t.datetime :started_at
      t.datetime :ended_at
      t.timestamps
    end

    add_index :product_experiments, [:product_id, :status]

    create_table :product_experiment_variants do |t|
      t.references :product_experiment, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description_override
      t.integer :price_cents_override
      t.integer :weight, default: 1, null: false
      t.integer :traffic_count, default: 0, null: false
      t.integer :conversion_count, default: 0, null: false
      t.timestamps
    end

    create_table :product_experiment_assignments do |t|
      t.references :product_experiment, null: false, foreign_key: true
      t.references :product_experiment_variant, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :buyer_cookie
      t.datetime :assigned_at, null: false
      t.datetime :converted_at
      t.references :purchase, null: true, foreign_key: true
      t.timestamps
    end

    add_index :product_experiment_assignments, [:product_experiment_id, :user_id], unique: true, where: "user_id IS NOT NULL"
    add_index :product_experiment_assignments, [:product_experiment_id, :buyer_cookie], unique: true, where: "buyer_cookie IS NOT NULL AND user_id IS NULL"
  end
end
