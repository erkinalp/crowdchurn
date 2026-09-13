# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Shared communities" do
  let(:seller) { create(:user) }
  let(:source_product) { create(:product, user: seller, community_chat_enabled: true) }
  let!(:community) { create(:community, seller:, resource: source_product) }
  let(:product) { create(:product, user: seller) }

  describe "community selection" do
    it "switches between an own community and a shared community without losing messages" do
      product.toggle_community_chat!(true)
      own_community = product.effective_community
      message = create(:community_chat_message, community: own_community, user: seller)

      product.toggle_community_chat!(true, shared_community_id: community.external_id)

      expect(product.effective_community).to eq(community)
      expect(product.active_community).to be_nil
      expect(own_community.reload).to be_deleted
      expect(product).to be_community_chat_enabled

      product.toggle_community_chat!(true, shared_community_id: nil)

      expect(product.effective_community).to eq(own_community)
      expect(own_community.reload).to be_alive
      expect(own_community.community_chat_messages).to eq([message])
      expect(product.community_products).to be_empty
      expect(community.reload).to be_alive
    end

    it "preserves an existing shared selection when enabling without a selection" do
      product.toggle_community_chat!(true, shared_community_id: community.external_id)
      association_id = product.community_products.sole.id

      product.toggle_community_chat!(true)
      product.toggle_community_chat!(true, shared_community_id: community.external_id)

      expect(product.effective_community).to eq(community)
      expect(product.community_products.sole.id).to eq(association_id)
      expect(product.communities).to be_empty
    end

    it "switches between shared communities" do
      other_community = create(:community, seller:, resource: create(:product, user: seller, community_chat_enabled: true))
      product.toggle_community_chat!(true, shared_community_id: community.external_id)

      product.toggle_community_chat!(true, shared_community_id: other_community.external_id)

      expect(product.effective_community).to eq(other_community)
      expect(community.linked_products).to be_empty
      expect(other_community.linked_products).to eq([product])
    end

    it "disables a linked product without disabling the shared community" do
      product.toggle_community_chat!(true, shared_community_id: community.external_id)

      product.toggle_community_chat!(false)

      expect(product).not_to be_community_chat_enabled
      expect(product.effective_community).to be_nil
      expect(product.community_products).to be_empty
      expect(community.reload).to be_alive
    end

    it "keeps a shared community active when its source product disables chat" do
      product.toggle_community_chat!(true, shared_community_id: community.external_id)

      source_product.toggle_community_chat!(false)

      expect(community.reload).to be_alive
      expect(product.reload.effective_community).to eq(community)
      expect(seller.accessible_communities_ids).to eq([community.id])

      product.toggle_community_chat!(false)

      expect(community.reload).to be_deleted
      expect(seller.accessible_communities_ids).to be_empty
    end

    it "retains a shared community when its source product switches to another community" do
      product.toggle_community_chat!(true, shared_community_id: community.external_id)
      another_community = create(:community, seller:, resource: create(:product, user: seller, community_chat_enabled: true))

      source_product.toggle_community_chat!(true, shared_community_id: another_community.external_id)

      expect(community.reload).to be_alive
      expect(product.reload.effective_community).to eq(community)
      expect(source_product.effective_community).to eq(another_community)

      product.toggle_community_chat!(false)

      expect(community.reload).to be_deleted
      expect(another_community.reload).to be_alive
    end

    it "does not delete a community when its own ID is submitted as the selection" do
      source_product.toggle_community_chat!(true, shared_community_id: community.external_id)

      expect(source_product.effective_community).to eq(community)
      expect(community.reload).to be_alive
      expect(source_product.community_products).to be_empty
    end

    it "rejects cross-seller and deleted community selections atomically" do
      other_community = create(:community)
      community.mark_deleted!

      [other_community.external_id, community.external_id, "missing-community"].each do |id|
        expect { product.toggle_community_chat!(true, shared_community_id: id) }
          .to raise_error(Link::LinkInvalid, "Invalid community")
        expect(product.reload).not_to be_community_chat_enabled
        expect(product.community_products).to be_empty
      end
    end
  end

  describe "buyer access" do
    let(:buyer) { create(:user) }

    before { product.toggle_community_chat!(true, shared_community_id: community.external_id) }

    it "grants access to buyers of any linked product and deduplicates purchases" do
      create(:purchase, link: product, purchaser: buyer)
      create(:purchase, link: source_product, purchaser: buyer)

      expect(buyer.accessible_communities_ids).to eq([community.id])
      expect(CommunityPolicy.new(SellerContext.new(user: buyer, seller: buyer), community).show?).to be(true)
    end

    it "recognizes purchases made with the account email" do
      create(:purchase, link: product, purchaser: nil, email: buyer.email)

      expect(buyer.accessible_communities_ids).to eq([community.id])
    end

    it "rejects a buyer without a successful purchase" do
      create(:purchase, link: product, purchaser: buyer, purchase_state: "failed")

      expect(buyer.accessible_communities_ids).to be_empty
    end

    it "revokes access when the purchased linked product disables chat" do
      create(:purchase, link: product, purchaser: buyer)
      product.toggle_community_chat!(false)

      expect(buyer.accessible_communities_ids).to be_empty
      expect(community.reload).to be_alive
    end

    it "revokes access when the purchased linked product is deleted" do
      create(:purchase, link: product, purchaser: buyer)
      product.mark_deleted!

      expect(buyer.accessible_communities_ids).to be_empty
    end

    it "retains linked-product access when the source product is deleted" do
      create(:purchase, link: product, purchaser: buyer)
      source_product.mark_deleted!

      expect(buyer.accessible_communities_ids).to eq([community.id])
      expect(seller.accessible_communities_ids).to eq([community.id])
    end

    it "retains linked-product access when the source product disables chat" do
      create(:purchase, link: product, purchaser: buyer)
      source_buyer = create(:user)
      create(:purchase, link: source_product, purchaser: source_buyer)
      source_product.toggle_community_chat!(false)

      expect(buyer.accessible_communities_ids).to eq([community.id])
      expect(source_buyer.accessible_communities_ids).to be_empty
    end

    it "moves source-product buyers to the newly selected community" do
      create(:purchase, link: source_product, purchaser: buyer)
      another_community = create(:community, seller:, resource: create(:product, user: seller, community_chat_enabled: true))
      source_product.toggle_community_chat!(true, shared_community_id: another_community.external_id)

      expect(buyer.accessible_communities_ids).to eq([another_community.id])
    end

    it "never grants access to a deleted shared community" do
      create(:purchase, link: product, purchaser: buyer)
      community.mark_deleted!

      expect(buyer.accessible_communities_ids).to be_empty
    end
  end
end
