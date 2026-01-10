# frozen_string_literal: true

class AutomatedMessageReply < ApplicationRecord
  belongs_to :automated_message
  belongs_to :sender, class_name: 'User'
  belongs_to :recipient, class_name: 'User'

  validates :message_body, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :for_user, ->(user) { where(recipient: user) }
  scope :recent, -> { order(created_at: :desc) }

  after_create :mark_original_as_replied
  after_create :notify_recipient

  def mark_as_read!
    update!(read_at: Time.current) if read_at.nil?
  end

  private

  def mark_original_as_replied
    # If this is a buyer replying to the automated message
    if sender == automated_message.user
      automated_message.mark_buyer_replied!
    end
  end

  def notify_recipient
    # Notify the recipient of the reply
    AutomatedMessageReplyMailer.new_reply(id).deliver_later
  end
end
