# frozen_string_literal: true

class Api::V2::DistributionRulesController < Api::V2::BaseController
  before_action(only: [:index, :show]) { doorkeeper_authorize!(*Doorkeeper.configuration.public_scopes.concat([:view_public])) }
  before_action(only: [:create, :update, :destroy]) { doorkeeper_authorize! :edit_products }
  before_action :fetch_product
  before_action :fetch_post
  before_action :fetch_post_variant
  before_action :fetch_distribution_rule, only: [:show, :update, :destroy]

  def index
    success_with_object(:distribution_rules, @post_variant.variant_distribution_rules.map { |r| distribution_rule_json(r) })
  end

  def create
    distribution_rule = @post_variant.variant_distribution_rules.new(permitted_params)
    if distribution_rule.save
      success_with_distribution_rule(distribution_rule)
    else
      error_with_creating_object(:distribution_rule, distribution_rule)
    end
  end

  def show
    success_with_distribution_rule(@distribution_rule)
  end

  def update
    if @distribution_rule.update(permitted_params)
      success_with_distribution_rule(@distribution_rule)
    else
      error_with_distribution_rule(@distribution_rule)
    end
  end

  def destroy
    if @distribution_rule.destroy
      success_with_distribution_rule
    else
      error_with_distribution_rule(@distribution_rule)
    end
  end

  private
    def permitted_params
      params.permit(:base_variant_id, :distribution_type, :distribution_value)
    end

    def fetch_post
      @post = @product.installments.alive.find_by_external_id(params[:post_id])
      error_with_object(:post, nil) if @post.nil?
    end

    def fetch_post_variant
      @post_variant = @post.post_variants.find_by_external_id(params[:post_variant_id])
      error_with_object(:post_variant, nil) if @post_variant.nil?
    end

    def fetch_distribution_rule
      @distribution_rule = @post_variant.variant_distribution_rules.find_by(id: params[:id])
      error_with_distribution_rule if @distribution_rule.nil?
    end

    def distribution_rule_json(rule)
      {
        id: rule.id,
        post_variant_id: rule.post_variant.external_id,
        base_variant_id: rule.base_variant_id,
        distribution_type: rule.distribution_type,
        distribution_value: rule.distribution_value
      }
    end

    def success_with_distribution_rule(distribution_rule = nil)
      success_with_object(:distribution_rule, distribution_rule.present? ? distribution_rule_json(distribution_rule) : nil)
    end

    def error_with_distribution_rule(distribution_rule = nil)
      error_with_object(:distribution_rule, distribution_rule)
    end
end
