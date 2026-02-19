# frozen_string_literal: true

class FundCart::ContributeService
  attr_reader :purchase

  def initialize(purchase:)
    @purchase = purchase
  end

  def perform
    fund_cart = purchase.link.fund_cart
    return if fund_cart.blank?

    amount_cents = purchase.price_cents

    fund_cart.with_lock do
      fund_cart.update!(balance_cents: fund_cart.balance_cents + amount_cents)
    end

    FundCart::AllocateFundsService.new(fund_cart: fund_cart).perform
  end
end
