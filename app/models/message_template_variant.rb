# frozen_string_literal: true

class MessageTemplateVariant < ApplicationRecord
  belongs_to :message_template

  validates :variant_name, presence: true, length:

 { maximum: 255 }
  validates :message_body, presence: true
  validates :weight, numericality: { greater_than_or_equal_to: 0 }
  validates :variant_name, uniqueness: { scope: :message_template_id }

  def read_rate
    return 0 if sent_count.zero?
    (read_count.to_f / sent_count * 100).round(2)
  end

  def reply_rate
    return 0 if sent_count.zero?
    (reply_count.to_f / sent_count * 100).round(2)
  end
end
