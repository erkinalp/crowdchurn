# frozen_string_literal: true

require "spec_helper"

describe BlackFridayStatsService do
  describe ".calculate_stats" do
    it "returns zeroed stats when no data exists" do
      stats = described_class.calculate_stats

      expect(stats[:active_deals_count]).to eq(0)
      expect(stats[:revenue_cents]).to eq(0)
      expect(stats[:average_discount_percentage]).to eq(0)
    end

    context "with indexed Black Friday data", :elasticsearch_wait_for_refresh do
      let(:creator) { create(:recommendable_user) }
      let(:black_friday_code) { SearchProducts::BLACK_FRIDAY_CODE }
      let(:other_code) { "WINTER2025" }

      before do
        Link.__elasticsearch__.create_index!(force: true)

        @product_25 = create_product_with_offer!(creator:, code: black_friday_code, amount_percentage: 25)
        @product_50 = create_product_with_offer!(creator:, code: black_friday_code, amount_percentage: 50)
        @product_fixed = create_product_with_offer!(creator:, code: black_friday_code, amount_cents: 2_000)

        @non_black_friday_product = create(:product, :recommendable, user: creator, price_cents: 8_000)
        @non_black_friday_offer = create(:offer_code, user: creator, code: other_code, amount_percentage: 10, products: [])
        @non_black_friday_product.offer_codes << @non_black_friday_offer

        index_model_records(Link)

        create_purchase_for(@product_25, created_at: 5.days.ago)
        create_purchase_for(@product_50, created_at: 2.days.ago)
        create_purchase_for(@product_fixed, created_at: 1.day.ago)

        create_purchase_for(@product_25, created_at: 40.days.ago) # outside window
        create_purchase_for(@product_50, created_at: 3.days.ago, refunded: true) # refunded
        create_purchase_for({ product: @non_black_friday_product, offer_code: @non_black_friday_offer }, created_at: 4.days.ago)

        index_model_records(Purchase)
      end

      it "returns the correct stats" do
        stats = described_class.calculate_stats

        expect(stats[:active_deals_count]).to eq(3)
        expect(stats[:revenue_cents]).to eq(20_500)
        expect(stats[:average_discount_percentage]).to eq(31.67)
      end
    end
  end

  describe ".fetch_stats" do
    before { Rails.cache.clear }
    after { Rails.cache.clear }

    it "caches values between calls" do
      expect(described_class).to receive(:calculate_stats).once.and_call_original
      first = described_class.fetch_stats
      second = described_class.fetch_stats

      expect(second).to eq(first)
    end

    it "uses configured cache key and expiration" do
      expect(Rails.cache).to receive(:fetch).with("black_friday_stats", expires_in: 10.minutes).and_call_original
      described_class.fetch_stats
    end

    it "stores the results in cache" do
      expect(described_class).to receive(:calculate_stats).once.and_call_original
      result = described_class.fetch_stats
      described_class.fetch_stats # verify that calculate_stats is called only once

      expect(Rails.cache.read("black_friday_stats")).to eq(result)
    end

    it "recomputes after cache expiration" do
      travel_to Time.current do
        described_class.fetch_stats
        travel 11.minutes
        expect(described_class).to receive(:calculate_stats).and_call_original
        described_class.fetch_stats
      end
    end

    it "recomputes after cache deletion" do
      described_class.fetch_stats
      Rails.cache.delete("black_friday_stats")
      expect(described_class).to receive(:calculate_stats).and_call_original
      described_class.fetch_stats
    end
  end

  def create_product_with_offer!(creator:, code:, amount_percentage: nil, amount_cents: nil)
    product = create(:product, :recommendable, user: creator, price_cents: 10_000)
    Purchase.destroy_by link: product # cleanup the purchases created by the factory
    offer_attrs = { user: creator, code:, products: [] }
    offer_attrs[:amount_percentage] = amount_percentage if amount_percentage
    offer_attrs[:amount_cents] = amount_cents if amount_cents
    offer_code = create(:offer_code, **offer_attrs)
    offer_code.update!(created_at: 5.days.ago)
    product.offer_codes << offer_code
    { product:, offer_code: }
  end

  def create_purchase_for(entry, created_at:, refunded: false)
    product = entry[:product]
    offer_code = entry[:offer_code]
    final_price = discounted_price_for(product, offer_code)

    travel_to(created_at) do
      purchase = create(
        :purchase,
        link: product,
        purchase_state: "successful",
        stripe_refunded: refunded
      )
      purchase.update_columns(
        price_cents: final_price,
        displayed_price_cents: final_price,
        total_transaction_cents: final_price
      )
      PurchaseOfferCodeDiscount.create!(
        purchase:,
        offer_code:,
        offer_code_amount: offer_code.is_percent? ? offer_code.amount_percentage : offer_code.amount_cents,
        offer_code_is_percent: offer_code.is_percent?,
        pre_discount_minimum_price_cents: product.price_cents,
        created_at:
      )
      purchase
    end
  end

  def discounted_price_for(product, offer_code)
    if offer_code.is_percent?
      discount = (product.price_cents * (offer_code.amount_percentage / 100.0)).round
      product.price_cents - discount
    elsif offer_code.amount_cents.present?
      [product.price_cents - offer_code.amount_cents, 0].max
    else
      product.price_cents
    end
  end
end
