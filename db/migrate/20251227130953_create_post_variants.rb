# frozen_string_literal: true

class CreatePostVariants < ActiveRecord::Migration[7.1]
  def change
    create_table :post_variants do |t|
      t.references :installment, null: false, foreign_key: true, type: :integer
      t.string :name, null: false
      t.text :message, size: :long, null: false
      t.boolean :is_control, default: false, null: false

      t.timestamps
    end

    add_index :post_variants, [:installment_id, :is_control], name: "index_post_variants_on_installment_id_and_is_control"
  end
end
