# frozen_string_literal: true

class Api::V2::VariantAssignmentsController < Api::V2::BaseController
  before_action { doorkeeper_authorize!(*Doorkeeper.configuration.public_scopes.concat([:view_sales])) }
  before_action :fetch_product
  before_action :fetch_post
  before_action :fetch_post_variant

  RESULTS_PER_PAGE = 100

  def index
    assignments = @post_variant.variant_assignments.includes(:subscription).order(assigned_at: :desc)

    if params[:page_key].present?
      begin
        last_record_created_at, last_record_id = decode_page_key(params[:page_key])
      rescue ArgumentError
        return error_400("Invalid page_key.")
      end
      assignments = assignments.where("assigned_at <= ? AND id < ?", last_record_created_at, last_record_id)
    end

    paginated_assignments = assignments.limit(RESULTS_PER_PAGE + 1).to_a
    has_next_page = paginated_assignments.size > RESULTS_PER_PAGE
    paginated_assignments = paginated_assignments.first(RESULTS_PER_PAGE)
    additional_response = has_next_page ? pagination_info_for_assignment(paginated_assignments.last) : {}

    success_with_object(:variant_assignments, paginated_assignments.map { |a| assignment_json(a) }, additional_response)
  end

  private
    def fetch_post
      @post = @product.installments.alive.find_by_external_id(params[:post_id])
      error_with_object(:post, nil) if @post.nil?
    end

    def fetch_post_variant
      @post_variant = @post.post_variants.find_by_external_id(params[:post_variant_id])
      error_with_object(:post_variant, nil) if @post_variant.nil?
    end

    def assignment_json(assignment)
      {
        id: assignment.id,
        post_variant_id: assignment.post_variant.external_id,
        subscription_id: assignment.subscription.external_id,
        assigned_at: assignment.assigned_at.iso8601
      }
    end

    def pagination_info_for_assignment(record)
      next_page_key = record.assigned_at.to_fs(:usec) + "-" + ObfuscateIds.encrypt_numeric(record.id).to_s
      {
        next_page_key:,
        next_page_url: next_page_url(next_page_key)
      }
    end
end
