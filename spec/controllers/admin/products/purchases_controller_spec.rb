# frozen_string_literal: true

require "spec_helper"
require "shared_examples/admin_base_controller_concern"

describe Admin::Products::PurchasesController do
  it_behaves_like "inherits from Admin::BaseController"

  let(:admin_user) { create(:admin_user) }

  before do
    sign_in admin_user
  end

  describe "GET index" do
    let(:product) { create(:product) }
    let!(:purchase) { create(:purchase, link: product) }

    it "returns purchases and pagination" do
      get :index, params: { product_id: product.id }, format: :json

      expect(response).to have_http_status(:ok)

      purchases = response.parsed_body["purchases"]
      expect(purchases).to be_present
      expect(purchases.length).to eq(1)
      expect(purchases.first["id"]).to eq(purchase.id)

      expect(response.parsed_body["pagination"]).to be_present
    end

    it "returns only purchases for the specified product" do
      other_product = create(:product)
      other_purchase = create(:purchase, link: other_product)

      get :index, params: { product_id: product.id }, format: :json

      expect(response).to have_http_status(:ok)

      purchases = response.parsed_body["purchases"]
      purchase_ids = purchases.map { |p| p["id"] }

      expect(purchase_ids).to include(purchase.id)
      expect(purchase_ids).not_to include(other_purchase.id)
    end

    context "with pagination parameters" do
      before do
        create_list(:purchase, 7, link: product)
      end

      it "accepts per_page and page parameters" do
        get :index, params: { product_id: product.id, per_page: 5, page: 1 }, format: :json

        expect(response).to have_http_status(:ok)

        purchases = response.parsed_body["purchases"]
        expect(purchases).to be_present
        expect(purchases.length).to eq(5)

        pagination = response.parsed_body["pagination"]
        expect(pagination).to be_present
      end

      it "returns the correct page of results" do
        get :index, params: { product_id: product.id, per_page: 5, page: 2 }, format: :json

        expect(response).to have_http_status(:ok)

        purchases = response.parsed_body["purchases"]
        expect(purchases).to be_present
        expect(purchases.length).to eq(3) # 8 total - 5 on page 1 = 3 on page 2
      end

      it "respects per_page limit" do
        get :index, params: { product_id: product.id, per_page: 3, page: 1 }, format: :json

        expect(response).to have_http_status(:ok)

        purchases = response.parsed_body["purchases"]
        expect(purchases.length).to eq(3)
      end
    end
  end

  describe "POST mass_refund" do
    let(:product) { create(:product) }
    let!(:successful_purchase) { create(:purchase, link: product) }
    let!(:failed_purchase) { create(:failed_purchase, link: product) }

    it "creates a batch and enqueues the job" do
      expect(MassRefundPurchasesWorker).to receive(:perform_async)

      post :mass_refund,
           params: { product_id: product.id, purchase_ids: [successful_purchase.id, failed_purchase.id] },
           format: :json

      body = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(body["success"]).to eq(true)
      expect(body["batch_id"]).to be_present
      expect(body["message"]).to include("Mass refund started")
    end

    it "requires purchase ids" do
      post :mass_refund, params: { product_id: product.id }, format: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to eq(false)
    end

    it "rejects purchases that do not belong to the product" do
      other_purchase = create(:purchase)

      post :mass_refund,
           params: { product_id: product.id, purchase_ids: [other_purchase.id] },
           format: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to eq(false)
    end
  end

  describe "GET mass_refund_batch" do
    let(:product) { create(:product) }
    let(:batch) { create(:mass_refund_batch, product:, status: :processing, refunded_count: 1, blocked_count: 1, failed_count: 0) }

    it "returns batch status" do
      get :mass_refund_batch, params: { product_id: product.id, id: batch.id }, format: :json

      body = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(body["id"]).to eq(batch.id)
      expect(body["status"]).to eq("processing")
      expect(body["refunded_count"]).to eq(1)
      expect(body["blocked_count"]).to eq(1)
      expect(body["failed_count"]).to eq(0)
    end

    it "returns 404 for batch not belonging to product" do
      other_product = create(:product)
      batch.update!(product: other_product)

      expect do
        get :mass_refund_batch, params: { product_id: product.id, id: batch.id }, format: :json
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
