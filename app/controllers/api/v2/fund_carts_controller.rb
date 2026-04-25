# frozen_string_literal: true

class Api::V2::FundCartsController < Api::V2::BaseController
  before_action { doorkeeper_authorize! :edit_products }

  def index
    fund_cart_links = current_resource_owner.links.where(native_type: "fund_cart").includes(:fund_cart).order(created_at: :desc)

    fund_carts = fund_cart_links.filter_map do |link|
      next if link.fund_cart.blank?

      fund_cart_json(link.fund_cart)
    end

    render_response(true, fund_carts:)
  end

  def show
    fund_cart = find_fund_cart
    return if fund_cart.nil?

    success_with_object(:fund_cart, fund_cart_json(fund_cart))
  end

  private
    def find_fund_cart
      fund_cart = FundCart.find_by_external_id(params[:id])
      if fund_cart.blank? || fund_cart.link.user_id != current_resource_owner.id
        error_with_object(:fund_cart, nil)
        return nil
      end
      fund_cart
    end

    def fund_cart_json(fund_cart)
      {
        id: fund_cart.external_id,
        product_id: fund_cart.link.external_id,
        product_name: fund_cart.link.name,
        balance_subunits: fund_cart.balance_subunits,
        currency: fund_cart.currency,
        pending_items_count: fund_cart.fund_cart_items.where(state: "pending").count,
        purchased_items_count: fund_cart.fund_cart_items.where(state: "purchased").count,
      }
    end
end
