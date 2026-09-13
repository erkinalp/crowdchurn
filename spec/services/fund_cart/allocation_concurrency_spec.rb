# frozen_string_literal: true

require "timeout"

describe FundCart::AllocateFundsService, "reservation concurrency" do
  self.use_transactional_tests = false

  before do
    @buyer = create(:user, created_at: 1.year.ago, country: "United States", state: "OR", zip_code: "97035")
    @seller = create(:user)
    @cart = create(:fund_cart_product, user: @buyer).fund_cart
    @products = 2.times.map { create(:product, user: @seller, price_cents: 1000) }
    @items = @products.map { |product| @cart.fund_cart_items.create!(product:) }
    @operator_existed = MerchantAccount.operator(StripeChargeProcessor.charge_processor_id).present?
    @lot = back_fund_cart(@cart, net_subunits: 1000)
    @quotes = @items.map { |item| FundCart::QuoteService.new(item:).perform }
  end

  after do
    if @cart
      settlement_ids = @cart.settlements.pluck(:id)
      FundCartLedgerEntry.where(fund_cart_id: @cart.id).delete_all
      FundCartSettlementAllocation.where(fund_cart_settlement_id: settlement_ids).delete_all
      FundCartSettlementOperation.where(fund_cart_id: @cart.id).delete_all
      FundCartSettlement.where(id: settlement_ids).delete_all
      FundCartFundingLot.where(fund_cart_id: @cart.id).delete_all
      purchase_ids = Purchase.where(link_id: [@cart.link_id, *@products.map(&:id)]).pluck(:id)
      PurchasePaymentFlow.where(purchase_id: purchase_ids).delete_all
      PurchaseSalesTaxInfo.where(purchase_id: purchase_ids).delete_all
      Purchase.where(id: purchase_ids).delete_all
      @cart.fund_cart_items.delete_all
      @cart.delete
      Price.where(link_id: [@cart.link_id, *@products.map(&:id)]).delete_all
      Link.where(id: [@cart.link_id, *@products.map(&:id)]).delete_all
    end
    MerchantAccount.where(id: @lot.source_merchant_account_id).delete_all if @lot && !@operator_existed
    User.where(id: [@buyer&.id, @seller&.id]).delete_all
  end

  it "does not reserve the same backing twice across independent database connections" do
    first_reserved = Queue.new
    second_waiting = Queue.new
    release_first = Queue.new
    connection_ids = Queue.new
    results = Queue.new
    threads = []
    allow_any_instance_of(FundCart).to receive(:with_lock).and_wrap_original do |method, *args, &block|
      second_waiting << true if Thread.current[:fund_cart_reservation_role] == :second
      method.call(*args) do
        result = block.call
        if Thread.current[:fund_cart_reservation_role] == :first
          first_reserved << true
          release_first.pop
        end
        result
      end
    end

    begin
      %i[first second].each_with_index do |role, index|
        threads << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection_ids << connection.object_id
            Thread.current[:fund_cart_reservation_role] = role
            cart = FundCart.find(@cart.id)
            results << described_class.new(fund_cart: cart).reserve!(item: @items[index], quote: @quotes[index])
          rescue FundCart::SettlementError => error
            results << error.code
          end
        end
        Timeout.timeout(5) { first_reserved.pop } if index.zero?
      end
      Timeout.timeout(5) { second_waiting.pop }
      release_first << true
      Timeout.timeout(10) { threads.each(&:value) }
      outcomes = 2.times.map { results.pop }
      expect(outcomes.count { |outcome| outcome.is_a?(FundCartSettlement) }).to eq(1)
      expect(outcomes).to include("insufficient_available_funds")
      expect(2.times.map { connection_ids.pop }.uniq.size).to eq(2)
      expect(@cart.settlements.count).to eq(1)
      expect(@lot.reload.reserved_subunits).to eq(1000)
      expect(@lot.available_subunits).to eq(0)
      expect(@cart.ledger_entries.sum(:amount_subunits)).to eq(0)
    ensure
      release_first << true if release_first.empty?
      threads.each { |thread| thread.kill if thread.alive? }
    end
  end
end
