# frozen_string_literal: true

class AutomatedMessage < ApplicationRecord
  include ExternalId

  belongs_to :message_template
  belongs_to :purchase
  belongs_to :user # Recipient (buyer)
  belongs_to :sender, class_name: 'User'
  belongs_to :message_template_variant, optional: true
  has_many :automated_message_replies, dependent: :destroy

  validates :rendered_message, presence: true
  validates :sent_at, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :recent, -> { order(sent_at: :desc) }
  scope :for_inbox, ->(user) { where(user: user).recent }
  scope :for_creator, ->(creator) { where(sender: creator).recent }
  scope :with_replies, -> { where(buyer_replied: true) }

  after_create :deliver_notification
  after_create :increment_variant_sent_count

  def mark_as_read!
    return if read_at.present?

    transaction do
      update!(read_at: Time.current)
      message_template_variant&.increment!(:read_count)
    end
  end

  def mark_buyer_replied!
    return if buyer_replied?

    transaction do
      update!(buyer_replied: true)
      message_template_variant&.increment!(:reply_count)
    end
  end

  def can_reply?(current_user)
    # Buyer can reply if they're the recipient
    current_user == user
  end

  def conversation_thread
    # Get all replies in this conversation
    automated_message_replies.order(created_at: :asc)
  end

  private

  def deliver_notification
    # Send email notification
    AutomatedMessageMailer.new_message(id).deliver_later

    # Could also send push notification, in-app notification, etc.
  end

  def increment_variant_sent_count
    message_template_variant&.increment!(:sent_count)
  end
end
