# frozen_string_literal: true

class Api::Internal::FundCartItemsController < Api::Internal::BaseController
  before_action :authenticate_user!
  before_action :set_fund_cart
  before_action :authorize_seller!

  def index
    items = @fund_cart.fund_cart_items.includes(:product).order(created_at: :desc)
    render json: {
      items: items.map { |item| item_json(item) },
      balance_cents: @fund_cart.balance_cents,
      currency: @fund_cart.currency,
    }
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
    return render json: { error: "Only pending items can be removed" }, status: :unprocessable_entity if item.state != "pending"

    item.mark_removed!
    render json: { success: true }
  end

  private
    def set_fund_cart
      @fund_cart = FundCart.find_by_external_id(params[:fund_cart_id])
      render json: { error: "Fund cart not found" }, status: :not_found if @fund_cart.blank?
    end

    def authorize_seller!
      return if @fund_cart.blank?

      if @fund_cart.user_id != current_user.id
        render json: { error: "Unauthorized" }, status: :forbidden
      end
    end

    def item_json(item)
      {
        id: item.external_id,
        product_id: item.product.external_id,
        product_name: item.product.name,
        product_price_cents: item.product.price_cents,
        product_native_type: item.product.native_type,
        state: item.state,
        purchased_at: item.purchased_at&.iso8601,
        created_at: item.created_at.iso8601,
      }
    end
end
