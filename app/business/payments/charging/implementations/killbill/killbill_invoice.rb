# frozen_string_literal: true

class KillbillInvoice
  attr_reader :invoice

  delegate :invoice_id, :account_id, :invoice_number, :invoice_date,
           :target_date, :currency, :status, :balance, :amount,
           :credit_adj, :refund_adj, :items, to: :invoice, allow_nil: true

  INVOICE_STATUS_DRAFT = "DRAFT"
  INVOICE_STATUS_COMMITTED = "COMMITTED"
  INVOICE_STATUS_VOID = "VOID"

  def initialize(invoice)
    @invoice = invoice
  end

  def id
    invoice_id
  end

  def amount_cents
    (amount.to_f * 100).to_i
  end

  def balance_cents
    (balance.to_f * 100).to_i
  end

  def paid?
    balance_cents <= 0 && status == INVOICE_STATUS_COMMITTED
  end

  def draft?
    status == INVOICE_STATUS_DRAFT
  end

  def committed?
    status == INVOICE_STATUS_COMMITTED
  end

  def voided?
    status == INVOICE_STATUS_VOID
  end

  def due_date
    target_date
  end

  def line_items
    return [] unless items.present?

    items.map { |item| KillbillInvoiceItem.new(item) }
  end

  def to_h
    {
      id: invoice_id,
      account_id: account_id,
      invoice_number: invoice_number,
      invoice_date: invoice_date,
      target_date: target_date,
      currency: currency,
      status: status,
      amount_cents: amount_cents,
      balance_cents: balance_cents,
      paid: paid?,
      items: line_items.map(&:to_h)
    }
  end
end

class KillbillInvoiceItem
  attr_reader :item

  delegate :invoice_item_id, :invoice_id, :account_id, :subscription_id,
           :plan_name, :phase_name, :item_type, :description,
           :start_date, :end_date, :amount, :currency, to: :item, allow_nil: true

  def initialize(item)
    @item = item
  end

  def id
    invoice_item_id
  end

  def amount_cents
    (amount.to_f * 100).to_i
  end

  def to_h
    {
      id: invoice_item_id,
      invoice_id: invoice_id,
      subscription_id: subscription_id,
      plan_name: plan_name,
      item_type: item_type,
      description: description,
      start_date: start_date,
      end_date: end_date,
      amount_cents: amount_cents,
      currency: currency
    }
  end
end
