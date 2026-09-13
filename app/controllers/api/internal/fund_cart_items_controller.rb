# frozen_string_literal: true

class Api::Internal::FundCartItemsController < Api::Internal::BaseController
  include FundCartItemRemoval

  before_action :authenticate_user!
  before_action :set_fund_cart
  before_action :authorize_seller!

  def index
    items = @fund_cart.fund_cart_items.includes(:product).order(created_at: :desc)
    render json: FundCartPresenter.new(@fund_cart).funds_props.merge(items: items.map { |item| item_json(item) })
  end

  def create
    product = Link.find_by_external_id(params[:product_id])
    return render json: { error: "Product not found" }, status: :not_found if product.blank?

    item, error = FundCart::AddItemService.new(fund_cart: @fund_cart, product: product).perform

    if error.present?
      render json: { error: error }, status: :unprocessable_entity
    else
      render json: { item: item_json(item) }, status: :created
    end
  end

  def destroy
    item = @fund_cart.fund_cart_items.find_by_external_id(params[:id])
    return render json: { error: "Item not found" }, status: :not_found if item.blank?

    remove_fund_cart_item!(item)
    render json: { success: true }
  rescue FundCart::SettlementError => error
    status = error.code == "only_pending_items_can_be_removed" ? :unprocessable_entity : :conflict
    render json: { error: FundCartPresenter.reason(error.code)[:message], error_code: error.code, item: item_json(item.reload) }, status:
  end

  private
    def set_fund_cart
      @fund_cart = FundCart.find_by_external_id(params[:fund_cart_id])
      render json: { error: "Fund cart not found" }, status: :not_found if @fund_cart.blank?
    end

    def authorize_seller!
      return if @fund_cart.blank?

      if @fund_cart.user_id != current_user.id || @fund_cart.link.user_id != current_user.id
        render json: { error: "Unauthorized" }, status: :forbidden
      end
    end

    def item_json(item)
      FundCartPresenter.new(@fund_cart).item_props(item)
    end
end
