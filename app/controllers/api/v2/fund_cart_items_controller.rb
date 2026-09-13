# frozen_string_literal: true

class Api::V2::FundCartItemsController < Api::V2::BaseController
  include FundCartItemRemoval

  before_action { doorkeeper_authorize! :edit_products }
  before_action :set_fund_cart

  def index
    items = @fund_cart.fund_cart_items.includes(:product).order(created_at: :desc)

    render_response(true, items: items.map { |item| item_json(item) }, fund_cart: FundCartPresenter.new(@fund_cart).api_props)
  end

  def create
    product = Link.find_by_external_id(params[:product_id])
    if product.blank?
      return error_with_object(:item, nil)
    end

    item, error = FundCart::AddItemService.new(fund_cart: @fund_cart, product: product).perform

    if error.present?
      render_response(false, message: error)
    else
      success_with_object(:item, item_json(item))
    end
  end

  def destroy
    item = @fund_cart.fund_cart_items.find_by_external_id(params[:id])
    return error_with_object(:item, nil) if item.blank?

    remove_fund_cart_item!(item)
    success_with_object(:item, nil)
  rescue FundCart::SettlementError => error
    render_response(false, message: FundCartPresenter.reason(error.code)[:message], error_code: error.code, item: item_json(item.reload))
  end

  private
    def set_fund_cart
      @fund_cart = FundCart.find_by_external_id(params[:fund_cart_id])
      if @fund_cart.blank? || @fund_cart.user_id != current_resource_owner.id || @fund_cart.link.user_id != current_resource_owner.id
        error_with_object(:fund_cart, nil)
      end
    end

    def item_json(item)
      FundCartPresenter.new(@fund_cart).item_props(item)
    end
end
