# frozen_string_literal: true

require "spec_helper"

RSpec.describe CommunityProduct do
  describe "associations" do
    it { is_expected.to belong_to(:community) }
    it { is_expected.to belong_to(:product).class_name("Link") }
  end

  describe "validations" do
    subject(:community_product) { build(:community_product) }

    it { is_expected.to validate_uniqueness_of(:community_id).scoped_to(:product_id) }

    it "validates that community and product belong to the same seller" do
      seller = create(:user)
      other_seller = create(:user)
      product = create(:product, user: seller)
      other_product = create(:product, user: other_seller)
      community = create(:community, seller: seller, resource: product)

      community_product = build(:community_product, community: community, product: other_product)
      expect(community_product).not_to be_valid
      expect(community_product.errors[:base]).to include("Community and product must belong to the same seller")
    end

    it "is valid when community and product belong to the same seller" do
      seller = create(:user)
      product1 = create(:product, user: seller)
      product2 = create(:product, user: seller)
      community = create(:community, seller: seller, resource: product1)

      community_product = build(:community_product, community: community, product: product2)
      expect(community_product).to be_valid
    end
  end
end
