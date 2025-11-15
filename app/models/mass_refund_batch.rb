# frozen_string_literal: true

class MassRefundBatch < ApplicationRecord
  belongs_to :product, class_name: "Link"
  belongs_to :admin_user, class_name: "User"

  enum status: {
    pending: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }

  validates :purchase_ids, presence: true
  validates :product_id, presence: true
  validates :admin_user_id, presence: true

  before_validation :set_json_defaults

  def add_error(purchase_id, error_message)
    errors_hash = (errors_by_purchase_id || {}).dup
    errors_hash[purchase_id.to_s] = error_message

    update_column(:errors_by_purchase_id, errors_hash)
  end

  def total_count
    purchase_ids.size
  end

  def processed_count
    refunded_count + blocked_count + failed_count
  end

  def remaining_count
    total_count - processed_count
  end

  def completion_percentage
    return 0 if total_count.zero?
    (processed_count.to_f / total_count * 100).round
  end

  private
    def set_json_defaults
      self.purchase_ids ||= []
      self.errors_by_purchase_id ||= {}
    end
end
