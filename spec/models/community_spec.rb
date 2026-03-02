# frozen_string_literal: true

require "spec_helper"

RSpec.describe Community do
  subject(:community) { build(:community) }

  describe "associations" do
    it { is_expected.to belong_to(:seller).class_name("User") }
    it { is_expected.to belong_to(:resource) }
    it { is_expected.to have_many(:community_chat_messages).dependent(:destroy) }
    it { is_expected.to have_many(:last_read_community_chat_messages).dependent(:destroy) }
    it { is_expected.to have_many(:community_chat_recaps).dependent(:destroy) }
    it { is_expected.to have_many(:community_products).dependent(:destroy) }
    it { is_expected.to have_many(:linked_products).through(:community_products) }
  end

  describe "validations" do
    it { is_expected.to validate_uniqueness_of(:seller_id).scoped_to([:resource_id, :resource_type, :deleted_at]) }
  end

  describe "#name" do
    it "returns the resource name" do
      community = build(:community, resource: create(:product, name: "Test product"))

      expect(community.name).to eq("Test product")
    end

    it "returns the custom name when set" do
      community = create(:community, resource: create(:product, name: "Test product"), name: "Custom Community Name")

      expect(community.name).to eq("Custom Community Name")
    end

    it "falls back to resource name when custom name is blank" do
      community = build(:community, resource: create(:product, name: "Test product"), name: "")

      expect(community.name).to eq("Test product")
    end
  end

  describe "#thumbnail_url" do
    it "returns the resource thumbnail url for email" do
      community = build(:community, resource: create(:product))

      expect(community.thumbnail_url).to eq(ActionController::Base.helpers.asset_url("native_types/thumbnails/digital.png"))
    end
  end

  describe "#all_products" do
    it "returns the resource product and all linked products" do
      seller = create(:user)
      product1 = create(:product, user: seller)
      product2 = create(:product, user: seller)
      community = create(:community, seller: seller, resource: product1)
      create(:community_product, community: community, product: product2)

      expect(community.all_products).to contain_exactly(product1, product2)
    end

    it "returns only the resource product when no linked products exist" do
      seller = create(:user)
      product = create(:product, user: seller)
      community = create(:community, seller: seller, resource: product)

      expect(community.all_products).to contain_exactly(product)
    end
  end

  describe "#add_product!" do
    it "links a product to the community" do
      seller = create(:user)
      product1 = create(:product, user: seller)
      product2 = create(:product, user: seller)
      community = create(:community, seller: seller, resource: product1)

      expect { community.add_product!(product2) }.to change { community.community_products.count }.by(1)
      expect(community.linked_products).to include(product2)
    end

    it "raises an error if the product belongs to a different seller" do
      seller = create(:user)
      other_seller = create(:user)
      product1 = create(:product, user: seller)
      product2 = create(:product, user: other_seller)
      community = create(:community, seller: seller, resource: product1)

      expect { community.add_product!(product2) }.to raise_error(ArgumentError, "Product must belong to the same seller")
    end

    it "is idempotent when adding the same product twice" do
      seller = create(:user)
      product1 = create(:product, user: seller)
      product2 = create(:product, user: seller)
      community = create(:community, seller: seller, resource: product1)

      community.add_product!(product2)
      expect { community.add_product!(product2) }.not_to change { community.community_products.count }
    end
  end

  describe "#remove_product!" do
    it "unlinks a product from the community" do
      seller = create(:user)
      product1 = create(:product, user: seller)
      product2 = create(:product, user: seller)
      community = create(:community, seller: seller, resource: product1)
      community.add_product!(product2)

      expect { community.remove_product!(product2) }.to change { community.community_products.count }.by(-1)
      expect(community.linked_products).not_to include(product2)
    end

    it "raises an error if the product is not linked" do
      seller = create(:user)
      product1 = create(:product, user: seller)
      product2 = create(:product, user: seller)
      community = create(:community, seller: seller, resource: product1)

      expect { community.remove_product!(product2) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
