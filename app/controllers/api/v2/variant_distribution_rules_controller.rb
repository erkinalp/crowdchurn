# frozen_string_literal: true

class Api::V2::VariantDistributionRulesController < Api::V2::BaseController
  before_action(only: [:index]) { doorkeeper_authorize!(*Doorkeeper.configuration.public_scopes.concat([:view_public])) }
  before_action(only: [:create, :update, :destroy]) { doorkeeper_authorize! :edit_products }
  before_action :fetch_post_variant
  before_action :fetch_distribution_rule, only: [:update, :destroy]

  def index
    success_with_object(:distribution_rules, @post_variant.variant_distribution_rules)
  end

  def create
    distribution_rule = @post_variant.variant_distribution_rules.build(permitted_params)
    if distribution_rule.save
      success_with_distribution_rule(distribution_rule)
    else
      error_with_creating_object(:distribution_rule, distribution_rule)
    end
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
      params.permit(:base_variant_id, :distribution_type, :distribution_value).tap do |p|
        if p[:base_variant_id].present?
          p[:base_variant_id] = BaseVariant.from_external_id(p[:base_variant_id])
        end
      end
    end

    def fetch_post_variant
      @post_variant = PostVariant.find_by_external_id(params[:post_variant_id])
      return error_with_object(:post_variant, nil) if @post_variant.nil?

      installment = @post_variant.installment
      product = installment.link
      error_with_object(:post_variant, nil) unless product&.user == current_resource_owner
    end

    def fetch_distribution_rule
      @distribution_rule = @post_variant.variant_distribution_rules.find_by_external_id(params[:id])
      error_with_distribution_rule(@distribution_rule) if @distribution_rule.nil?
    end

    def success_with_distribution_rule(distribution_rule = nil)
      success_with_object(:distribution_rule, distribution_rule)
    end

    def error_with_distribution_rule(distribution_rule = nil)
      error_with_object(:distribution_rule, distribution_rule)
    end
end
