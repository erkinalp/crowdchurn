# frozen_string_literal: true

class AddRecurrencePricesToProductExperimentVariants < ActiveRecord::Migration[7.1]
  def change
    add_column :product_experiment_variants, :recurrence_prices, :json
  end
end
