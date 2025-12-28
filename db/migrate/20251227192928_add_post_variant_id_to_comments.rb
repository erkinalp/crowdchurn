# frozen_string_literal: true

class AddPostVariantIdToComments < ActiveRecord::Migration[7.1]
  def change
    add_reference :comments, :post_variant, null: true, foreign_key: true
    add_index :comments, [:commentable_id, :commentable_type, :post_variant_id],
              name: "index_comments_on_commentable_and_post_variant"
  end
end
