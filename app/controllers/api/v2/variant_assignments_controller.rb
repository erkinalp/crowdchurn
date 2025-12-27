# frozen_string_literal: true

class Api::V2::VariantAssignmentsController < Api::V2::BaseController
  before_action { doorkeeper_authorize!(*Doorkeeper.configuration.public_scopes.concat([:view_public])) }
  before_action :fetch_post_variant

  def index
    assignments = @post_variant.variant_assignments.includes(:subscription)
    success_with_object(:assignments, assignments)
  end

  private
    def fetch_post_variant
      @post_variant = PostVariant.find_by_external_id(params[:post_variant_id])
      return error_with_object(:post_variant, nil) if @post_variant.nil?

      installment = @post_variant.installment
      product = installment.link
      error_with_object(:post_variant, nil) unless product&.user == current_resource_owner
    end
end
