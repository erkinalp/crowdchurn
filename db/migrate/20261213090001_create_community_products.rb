# frozen_string_literal: true

class CreateCommunityProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :community_products do |t|
      t.references :community, null: false, index: false
      t.references :product, null: false
      t.timestamps
      t.index [:community_id, :product_id], unique: true
    end

    add_column :communities, :name, :string
  end
end
