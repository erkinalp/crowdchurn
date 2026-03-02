# frozen_string_literal: true

class CreateCommunityProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :community_products do |t|
      t.references :community, null: false
      t.references :product, null: false

      t.timestamps

      t.index [:community_id, :product_id], unique: true
    end

    add_column :communities, :name, :string, after: :seller_id
  end
end
