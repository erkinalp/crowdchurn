# frozen_string_literal: true

class FundCartSettlementOperation < ApplicationRecord
  belongs_to :fund_cart
  belongs_to :fund_cart_settlement, optional: true
  belongs_to :fund_cart_funding_lot, optional: true
  belongs_to :purchase, optional: true
  belongs_to :refund, optional: true
  belongs_to :dispute, optional: true
  has_many :ledger_entries, class_name: "FundCartLedgerEntry", dependent: :restrict_with_exception

  validates :operation_key, presence: true, uniqueness: true
  validates :kind, presence: true
  validates :state, inclusion: { in: %w[pending processing completed failed cancelled reconciling] }
  scope :due, -> { where(state: "pending").where("available_at IS NULL OR available_at <= ?", Time.current) }

  after_create_commit :dispatch

  def dispatch
    if kind.in?(FundCart::RefundService::REFUND_KINDS)
      FundCartRefundJob.perform_async(id) if state.in?(%w[pending reconciling])
    elsif state == "pending"
      FundCartOperationJob.perform_async(id)
    end
  rescue StandardError => error
    Rails.logger.error("Fund cart outbox dispatch failed for operation #{id}: #{error.class}")
    nil
  end
end
