# frozen_string_literal: true

class FundCart < ApplicationRecord
  include NanoExternalId

  belongs_to :link
  belongs_to :user
  has_many :fund_cart_items, dependent: :destroy
  has_many :funding_lots, class_name: "FundCartFundingLot", dependent: :restrict_with_exception
  has_many :settlements, class_name: "FundCartSettlement", dependent: :restrict_with_exception
  has_many :ledger_entries, class_name: "FundCartLedgerEntry", dependent: :restrict_with_exception
  has_many :settlement_operations, class_name: "FundCartSettlementOperation", dependent: :restrict_with_exception

  validates :ledger_state, inclusion: { in: %w[legacy active reconciling paused] }

  validates :currency, presence: true
  validates :balance_subunits, numericality: { greater_than_or_equal_to: 0 }
  validate :currency_matches_link

  ITEM_TYPE_PRIORITY = {
    "digital" => 0,
    "course" => 0,
    "ebook" => 0,
    "physical" => 1,
    "print_book" => 1,
    "food" => 1,
    "bread" => 1,
    "literal_coffee" => 1,
    "bundle" => 2,
  }.freeze

  def pending_items
    fund_cart_items
      .where(state: "pending")
      .includes(:product)
      .sort_by { |item| [-item.product.price_cents, type_priority(item.product), item.id] }
  end

  def ledger_active?
    ledger_state == "active"
  end

  # Historical counters are not evidence of custody. Reconciliation must recover backing first.
  def activate_ledger!
    with_lock do
      return self if ledger_active?
      if balance_subunits != 0 || funding_lots.exists? || settlements.exists? || link.sales.where("price_cents > 0").exists?
        raise FundCart::SettlementError, "historical_cart_requires_reconciliation"
      end
      update!(ledger_state: "active", ledger_activated_at: Time.current, activation_evidence: { "kind" => "empty_cart" })
    end
    self
  end

  def available_subunits
    return 0 unless ledger_active? && debt_subunits.zero?
    funding_lots.where(state: "available", currency:).includes(:source_purchase).sum(&:authorized_available_subunits).to_i
  end

  def pending_subunits
    funding_lots.where(currency:).sum do |lot|
      if lot.state.in?(%w[pending reconciling])
        lot.confirmed_at? ? lot.available_subunits : lot.net_subunits
      elsif lot.state == "available" && (lot.confirmation_evidence["availability_verified"] == false || (lot.available_at && lot.available_at > Time.current))
        lot.available_subunits
      else
        0
      end
    end.to_i
  end

  def reserved_subunits
    funding_lots.where(currency:).sum(:reserved_subunits).to_i
  end

  def debt_subunits
    funding_lots.where(currency:).sum(:debt_subunits).to_i
  end

  def refresh_balance_projection!
    update!(balance_subunits: available_subunits)
  end

  private
    def currency_matches_link
      return if link.blank?

      if currency != link.price_currency_type
        errors.add(:currency, "must match the product's currency")
      end
    end

    def type_priority(product)
      ITEM_TYPE_PRIORITY.fetch(product.native_type, 0)
    end
end
