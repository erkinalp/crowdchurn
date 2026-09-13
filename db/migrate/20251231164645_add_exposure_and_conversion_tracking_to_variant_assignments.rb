# frozen_string_literal: true

class AddExposureAndConversionTrackingToVariantAssignments < ActiveRecord::Migration[7.1]
  def change
    change_table :variant_assignments, bulk: true do |t|
      t.datetime :exposed_at, null: true
      t.datetime :converted_at, null: true
      t.references :purchase, null: true, foreign_key: true

      t.index :exposed_at, where: "exposed_at IS NOT NULL", name: "index_variant_assignments_on_exposed_at"
      t.index :converted_at, where: "converted_at IS NOT NULL", name: "index_variant_assignments_on_converted_at"
    end
  end
end
