# frozen_string_literal: true

class Admin::Search::Purchases::PastChargebackedPurchasesController < Admin::Search::BaseController
  def index
    render json: {
      purchases: @purchase.find_past_chargebacked_purchases.as_json(admin: true),
    }
  end
end
