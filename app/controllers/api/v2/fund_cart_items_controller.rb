# frozen_string_literal: true

class Api::V2::FundCartItemsController < Api::V2::BaseController
  before_action { doorkeeper_authorize! :edit_products }
  before_action :set_fund_cart

  def index
    items = @fund_cart.fund_cart_items.includes(:product).order(created_at: :desc)

    render_response(true, items: items.map { |item| item_json(item) })
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

    if item.state != "pending"
      return render_response(false, message: "Only pending items can be removed")
    end

    item.mark_removed!
    success_with_object(:item, nil)
  end

  private
    def set_fund_cart
      @fund_cart = FundCart.find_by_external_id(params[:fund_cart_id])
      if @fund_cart.blank? || @fund_cart.link.user_id != current_resource_owner.id
        error_with_object(:fund_cart, nil)
      end
    end

    def item_json(item)
      {
        id: item.external_id,
        product_id: item.product.external_id,
        product_name: item.product.name,
        product_price_cents: item.product.price_cents,
        state: item.state,
        purchased_at: item.purchased_at&.iso8601,
        created_at: item.created_at.iso8601,
      }
    end
end
