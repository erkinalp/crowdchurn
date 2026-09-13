# frozen_string_literal: true

class AddProductInstallmentPlanToVariantDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_reference :variant_distribution_rules, :product_installment_plan, null: true, foreign_key: true
  end
end
