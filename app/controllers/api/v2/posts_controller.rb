# frozen_string_literal: true

class Api::V2::PostsController < Api::V2::BaseController
  before_action(only: [:index, :show]) { doorkeeper_authorize!(*Doorkeeper.configuration.public_scopes.concat([:view_public])) }
  before_action :fetch_product
  before_action :fetch_post, only: [:show]

  RESULTS_PER_PAGE = 10

  def index
    posts = @product.installments.alive.published.order(published_at: :desc)

    if params[:page_key].present?
      begin
        last_record_created_at, last_record_id = decode_page_key(params[:page_key])
      rescue ArgumentError
        return error_400("Invalid page_key.")
      end
      posts = posts.where("published_at <= ? AND id < ?", last_record_created_at, last_record_id)
    end

    paginated_posts = posts.limit(RESULTS_PER_PAGE + 1).to_a
    has_next_page = paginated_posts.size > RESULTS_PER_PAGE
    paginated_posts = paginated_posts.first(RESULTS_PER_PAGE)
    additional_response = has_next_page ? pagination_info(paginated_posts.last) : {}

    success_with_object(:posts, paginated_posts.map { |post| post_json_with_variant(post) }, additional_response)
  end

  def show
    success_with_post(@post)
  end

  private
    def fetch_post
      @post = @product.installments.alive.published.find_by_external_id(params[:id])
      error_with_post if @post.nil?
    end

    def post_json_with_variant(post)
      variant_info = assigned_variant_for_post(post)
      message = variant_info[:variant]&.message || post.message

      {
        id: post.external_id,
        name: post.name,
        message: message,
        published_at: post.published_at&.iso8601,
        has_ab_test: post.has_ab_test?,
        post_variants_count: post.post_variants.count,
        assigned_variant_id: variant_info[:variant]&.external_id
      }
    end

    def assigned_variant_for_post(post)
      return { variant: nil, assignment: nil } unless post.has_ab_test?

      user = current_resource_owner
      buyer_cookie = VariantPriceService.get_or_create_buyer_cookie(cookies)

      service = VariantPriceService.new(
        product: @product,
        installment: post,
        user: user,
        buyer_cookie: buyer_cookie
      )

      variant = service.assigned_variant
      return { variant: nil, assignment: nil } unless variant.present?

      service.record_exposure!

      { variant: variant, assignment: service.variant_assignment }
    end

    def success_with_post(post = nil)
      success_with_object(:post, post.present? ? post_json_with_variant(post) : nil)
    end

    def error_with_post(post = nil)
      error_with_object(:post, post)
    end
end
