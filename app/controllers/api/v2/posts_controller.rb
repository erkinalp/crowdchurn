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

    success_with_object(:posts, paginated_posts.map { |post| post_json(post) }, additional_response)
  end

  def show
    success_with_post(@post)
  end

  private
    def fetch_post
      @post = @product.installments.alive.published.find_by_external_id(params[:id])
      error_with_post if @post.nil?
    end

    def post_json(post)
      {
        id: post.external_id,
        name: post.name,
        message: post.message,
        published_at: post.published_at&.iso8601,
        has_ab_test: post.has_ab_test?,
        post_variants_count: post.post_variants.count
      }
    end

    def success_with_post(post = nil)
      success_with_object(:post, post.present? ? post_json(post) : nil)
    end

    def error_with_post(post = nil)
      error_with_object(:post, post)
    end
end
