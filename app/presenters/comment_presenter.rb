# frozen_string_literal: true

class CommentPresenter
  include UsersHelper
  include ActionView::Helpers::DateHelper

  attr_reader :comment, :pundit_user, :purchase, :show_variant_info
  delegate :author, to: :comment, allow_nil: true

  def initialize(pundit_user:, comment:, purchase:, show_variant_info: false)
    @pundit_user = pundit_user
    @comment = comment
    @purchase = purchase
    @show_variant_info = show_variant_info
  end

  def comment_component_props
    props = {
      id: comment.external_id,
      parent_id: comment.parent_id.presence && ObfuscateIds.encrypt(comment.parent_id),
      author_id: author&.external_id,
      author_name: author&.display_name || comment.author_name.presence,
      author_avatar_url: author&.avatar_url || ActionController::Base.helpers.asset_url("gumroad-default-avatar-5.png"),
      purchase_id: comment.purchase&.external_id,
      content: {
        original: comment.content,
        formatted: Rinku.auto_link(CGI.escapeHTML(comment.content), :all, %(target="_blank" rel="noopener noreferrer nofollow")),
      },
      depth: comment.depth,
      created_at: comment.created_at.iso8601,
      created_at_humanized: "#{time_ago_in_words(comment.created_at)} ago",
      is_editable: Pundit.policy!(pundit_user, comment_context).update?,
      is_deletable: Pundit.policy!(pundit_user, comment_context).destroy?
    }

    if show_variant_info && comment.post_variant.present?
      props[:variant] = {
        id: comment.post_variant.id,
        external_id: comment.post_variant.external_id,
        name: comment.post_variant.name
      }
    end

    props
  end

  private
    def comment_context
      @_comment_context ||= CommentContext.new(
        comment: @comment,
        commentable: nil,
        purchase: @purchase
      )
    end
end
