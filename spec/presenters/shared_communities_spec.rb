# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Shared community presenters" do
  include Rails.application.routes.url_helpers

  let(:seller) { create(:user) }
  let(:buyer) { create(:user) }
  let(:source_product) { create(:product, user: seller, name: "Writing course", community_chat_enabled: true) }
  let!(:community) { create(:community, seller:, resource: source_product, name: "Classroom") }
  let(:product) { create(:product, user: seller) }

  before { product.toggle_community_chat!(true, shared_community_id: community.external_id) }

  it "offers seller communities with custom names, excluding the product's own and other sellers' communities" do
    create(:community)
    deleted_community = create(:community, seller:, resource: create(:product, user: seller))
    deleted_community.mark_deleted!
    props = ProductPresenter.new(product:).edit_props[:product]

    expect(props[:shared_community_id]).to eq(community.external_id)
    expect(props[:available_communities]).to eq([{ id: community.external_id, name: "Classroom", product_name: "Writing course" }])
    expect(ProductPresenter.new(product: source_product).edit_props[:product][:available_communities]).to be_empty
  end

  it "includes the number of linked products" do
    props = CommunityPresenter.new(community:, current_user: seller).props

    expect(props[:name]).to eq("Classroom")
    expect(props[:linked_product_count]).to eq(1)
  end

  describe "download-page community links" do
    let(:purchase) { create(:purchase, link: product, purchaser: buyer) }
    let(:url_redirect) { create(:url_redirect, purchase:) }
    let(:presenter) { UrlRedirectPresenter.new(url_redirect:, logged_in_user: buyer) }

    it "links directly to the effective community for a signed-in buyer" do
      expect(presenter.download_page_with_content_props[:content][:community_chat_url])
        .to eq(community_path(seller.external_id, community.external_id))
    end

    it "retains login and guest signup redirects" do
      logged_out_presenter = UrlRedirectPresenter.new(url_redirect:, logged_in_user: nil)
      path = community_path(seller.external_id, community.external_id)
      expect(logged_out_presenter.download_page_with_content_props[:content][:community_chat_url])
        .to eq(login_path(email: purchase.email, next: path))

      purchase.update!(purchaser_id: nil)
      expect(logged_out_presenter.download_page_with_content_props[:content][:community_chat_url])
        .to eq(signup_path(email: purchase.email, next: path))
    end

    it "omits links when the purchased product is disabled or deleted" do
      product.toggle_community_chat!(false)
      expect(presenter.download_page_with_content_props[:content][:community_chat_url]).to be_nil

      product.toggle_community_chat!(true, shared_community_id: community.external_id)
      product.mark_deleted!
      expect(presenter.download_page_with_content_props[:content][:community_chat_url]).to be_nil
    end
  end
end
