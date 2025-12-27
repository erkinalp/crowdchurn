# frozen_string_literal: true

class Api::V2::PostVariantsController < Api::V2::BaseController
  before_action(only: [:index, :show]) { doorkeeper_authorize!(*Doorkeeper.configuration.public_scopes.concat([:view_public])) }
  before_action(only: [:create, :update, :destroy]) { doorkeeper_authorize! :edit_products }
  before_action :fetch_product
  before_action :fetch_installment
  before_action :fetch_post_variant, only: [:show, :update, :destroy]

  def index
    success_with_object(:post_variants, @installment.post_variants)
  end

  def create
    post_variant = @installment.post_variants.build(permitted_params)
    if post_variant.save
      success_with_post_variant(post_variant)
    else
      error_with_creating_object(:post_variant, post_variant)
    end
  end

  def show
    success_with_post_variant(@post_variant)
  end

  def update
    if @post_variant.update(permitted_params)
      success_with_post_variant(@post_variant)
    else
      error_with_post_variant(@post_variant)
    end
  end

  def destroy
    if @post_variant.destroy
      success_with_post_variant
    else
      error_with_post_variant(@post_variant)
    end
  end

  private
    def permitted_params
      params.permit(:name, :message, :is_control)
    end

    def fetch_installment
      @installment = @product.installments.find_by_external_id(params[:installment_id])
      error_with_object(:installment, nil) if @installment.nil?
    end

    def fetch_post_variant
      @post_variant = @installment.post_variants.find_by_external_id(params[:id])
      error_with_post_variant(@post_variant) if @post_variant.nil?
    end

    def success_with_post_variant(post_variant = nil)
      success_with_object(:post_variant, post_variant)
    end

    def error_with_post_variant(post_variant = nil)
      error_with_object(:post_variant, post_variant)
    end
end
