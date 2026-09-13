# frozen_string_literal: true

require "pagy/extras/standalone"

class PaginatedCommentsPresenter
  include Pagy::Backend

  COMMENTS_PER_PAGE = 20

  attr_reader :commentable, :pundit_user, :purchase, :options, :page, :variant_filter

  def initialize(pundit_user:, commentable:, purchase:, options: {})
    @pundit_user = pundit_user
    @commentable = commentable
    @purchase = purchase
    @options = options
    @page = [options[:page].to_i, 1].max
    @variant_filter = options[:variant_filter]
  end

  def result
    root_comments = filtered_comments.order(:created_at).roots
    pagination, paginated_root_comments = pagy(root_comments, limit: COMMENTS_PER_PAGE, url: "", page:)
    comments = comments_with_descendants(paginated_root_comments).includes(:commentable, :post_variant, author: { avatar_attachment: :blob }).alive
    comments = filter_descendants_by_variant(comments) unless is_seller?
    comments_json = comments.map do |comment|
      CommentPresenter.new(pundit_user:, comment:, purchase:, show_variant_info: is_seller?).comment_component_props
    end

    result_hash = {
      comments: comments_json,
      count: filtered_comments.count,
      pagination: PagyPresenter.new(pagination).metadata
    }

    result_hash[:variants] = variant_options if is_seller? && has_variants?
    result_hash
  end

  private
    def filtered_comments
      base_comments = commentable.comments.alive

      if is_seller?
        if variant_filter.present?
          base_comments.for_variant(variant_filter)
        else
          base_comments
        end
      else
        variant_info = find_assigned_variant_info
        if variant_info
          base_comments.visible_to_variant(variant_info[:id], variant_info[:external_id])
        else
          base_comments.unscoped_variant
        end
      end
    end

    def is_seller?
      return @_is_seller if defined?(@_is_seller)

      @_is_seller = pundit_user&.seller.present? && commentable.respond_to?(:seller_id) && pundit_user.seller.id == commentable.seller_id
    end

    def has_variants?
      return @_has_variants if defined?(@_has_variants)

      @_has_variants = commentable.respond_to?(:post_variants) && commentable.post_variants.exists?
    end

    def variant_options
      commentable.post_variants.map do |variant|
        { id: variant.id, name: variant.name, external_id: variant.external_id }
      end
    end

    def find_assigned_variant_info
      return nil unless purchase&.subscription_id.present?
      return nil unless has_variants?

      subscription = Subscription.find_by(id: purchase.subscription_id)
      return nil unless subscription

      post_variant_ids = commentable.post_variants.pluck(:id)
      assignment = VariantAssignment.joins(:post_variant).find_by(subscription_id: subscription.id, post_variant_id: post_variant_ids)
      return nil unless assignment

      { id: assignment.post_variant_id, external_id: assignment.post_variant.external_id }
    end

    def filter_descendants_by_variant(comments)
      variant_info = find_assigned_variant_info
      return comments.unscoped_variant unless variant_info

      comments.visible_to_variant(variant_info[:id], variant_info[:external_id])
    end

    def comments_with_descendants(comments)
      comments.inject(Comment.none) do |scope, parent|
        scope.or parent.subtree.order(:created_at).to_depth(Comment::MAX_ALLOWED_DEPTH)
      end
    end
end
