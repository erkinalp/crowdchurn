# frozen_string_literal: true

class Admin::Search::Purchases::BaseController < Admin::Search::BaseController
  before_action :fetch_purchase

  protected

    def fetch_purchase
      @purchase = Purchase.find(params[:purchase_id])
    end
end
