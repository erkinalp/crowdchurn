# frozen_string_literal: true

class Api::V2::PostCommentsController < Api::V2::BaseController
  before_action(only: [:index, :show]) { doorkeeper_authorize!(*Doorkeeper.configuration.public_scopes.concat([:view_public])) }
  before_action(only: [:create, :update, :destroy]) { doorkeeper_authorize! :edit_products }
  before_action :fetch_product
  before_action :fetch_post
  before_action :fetch_comment, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 20

  def index
    comments = @post.comments.alive

    if seller?
      if params[:variant_id].present?
        post_variant = @post.post_variants.find_by_external_id(params[:variant_id])
        return error_with_object(:post_variant, nil) if post_variant.nil?

        comments = comments.for_variant(post_variant.id)
      end
    else
      assigned_variant = subscriber_assigned_variant
      if assigned_variant.present?
        comments = comments.visible_to_variant_external_id(assigned_variant.external_id)
      else
        comments = comments.unscoped_variant
      end
    end

    comments = comments.order(created_at: :desc)

    if params[:page_key].present?
      begin
        last_record_created_at, last_record_id = decode_page_key(params[:page_key])
      rescue ArgumentError
        return error_400("Invalid page_key.")
      end
      comments = comments.where("created_at <= ? AND id < ?", last_record_created_at, last_record_id)
    end

    paginated_comments = comments.includes(:author, :post_variant).limit(RESULTS_PER_PAGE + 1).to_a
    has_next_page = paginated_comments.size > RESULTS_PER_PAGE
    paginated_comments = paginated_comments.first(RESULTS_PER_PAGE)
    additional_response = has_next_page ? pagination_info(paginated_comments.last) : {}

    success_with_object(:comments, paginated_comments.map { |c| comment_json(c) }, additional_response)
  end

  def show
    success_with_comment(@comment)
  end

  def create
    comment = @post.comments.new(permitted_create_params)
    comment.author_id = current_resource_owner.id
    comment.author_name = current_resource_owner.display_name
    comment.comment_type = Comment::COMMENT_TYPE_USER_SUBMITTED

    if seller?
      if params[:variant_ids].present?
        resolved_variants = resolve_variant_ids(params[:variant_ids])
        return if resolved_variants.nil?

        if resolved_variants.size == 1
          comment.post_variant_id = resolved_variants.first.id
        else
          comment.variant_ids = resolved_variants.map(&:external_id)
          comment.post_variant_id = resolved_variants.first.id
        end
      elsif params[:variant_id].present?
        post_variant = @post.post_variants.find_by_external_id(params[:variant_id])
        return error_with_object(:post_variant, nil) if post_variant.nil?

        comment.post_variant_id = post_variant.id
      end
    else
      assigned_variant = subscriber_assigned_variant
      if assigned_variant.present?
        comment.post_variant_id = assigned_variant.id
      end
    end

    if comment.save
      success_with_comment(comment)
    else
      error_with_creating_object(:comment, comment)
    end
  end

  def update
    if @comment.update(permitted_update_params)
      success_with_comment(@comment)
    else
      error_with_comment(@comment)
    end
  end

  def destroy
    if @comment.mark_deleted!
      success_with_comment
    else
      error_with_comment(@comment)
    end
  end

  private
    def permitted_create_params
      params.permit(:content, :parent_id)
    end

    def permitted_update_params
      params.permit(:content)
    end

    def fetch_post
      @post = @product.installments.alive.published.find_by_external_id(params[:post_id])
      error_with_object(:post, nil) if @post.nil?
    end

    def fetch_comment
      @comment = @post.comments.alive.find_by_external_id(params[:id])
      error_with_comment if @comment.nil?
    end

    def comment_json(comment)
      json = {
        id: comment.external_id,
        content: comment.content,
        author_id: comment.author&.external_id,
        author_name: comment.author&.display_name || comment.author_name,
        parent_id: comment.parent&.external_id,
        created_at: comment.created_at.iso8601,
        updated_at: comment.updated_at.iso8601
      }

      if comment.variant_ids.present?
        json[:variant_ids] = comment.variant_ids
        variants = @post.post_variants.where(external_id: comment.variant_ids)
        json[:variants] = variants.map { |v| { id: v.external_id, name: v.name } }
      elsif comment.post_variant.present?
        json[:variant] = {
          id: comment.post_variant.external_id,
          name: comment.post_variant.name
        }
        json[:variant_ids] = [comment.post_variant.external_id]
      end

      json
    end

    def success_with_comment(comment = nil)
      success_with_object(:comment, comment.present? ? comment_json(comment) : nil)
    end

    def error_with_comment(comment = nil)
      error_with_object(:comment, comment)
    end

    def seller?
      @product.user_id == current_resource_owner.id
    end

    def subscriber_assigned_variant
      subscription = current_resource_owner.subscriptions.find_by(link_id: @product.id)
      return nil unless subscription

      assignment = VariantAssignment.joins(:post_variant)
                                    .where(subscription_id: subscription.id)
                                    .where(post_variants: { installment_id: @post.id })
                                    .first
      assignment&.post_variant
    end

    def resolve_variant_ids(variant_ids_param)
      variant_ids_array = variant_ids_param.is_a?(Array) ? variant_ids_param : [variant_ids_param]
      resolved_variants = []

      variant_ids_array.each do |variant_id|
        post_variant = @post.post_variants.find_by_external_id(variant_id)
        if post_variant.nil?
          error_with_object(:post_variant, nil)
          return nil
        end
        resolved_variants << post_variant
      end

      resolved_variants
    end
end
