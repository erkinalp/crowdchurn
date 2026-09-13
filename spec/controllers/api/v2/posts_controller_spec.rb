# frozen_string_literal: true

require "spec_helper"

describe Api::V2::PostsController do
  let(:seller) { create(:user) }
  let(:product) { create(:product, user: seller) }
  let(:app) { create(:oauth_application, owner: create(:user)) }

  describe "GET 'index'" do
    let(:action) { :index }
    let(:params) { { link_id: product.external_id } }

    context "when logged in with public scope" do
      let(:token) { create("doorkeeper/access_token", application: app, resource_owner_id: seller.id, scopes: "view_public") }

      before do
        params.merge!(format: :json, access_token: token.token)
      end

      context "when product has posts" do
        let!(:post1) { create(:installment, :published, link: product, name: "Post 1", published_at: 1.day.ago) }
        let!(:post2) { create(:installment, :published, link: product, name: "Post 2", published_at: Time.current) }

        it "returns posts in descending order by published_at" do
          get action, params: params
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body["success"]).to be true
          expect(response.parsed_body["posts"].length).to eq(2)
          expect(response.parsed_body["posts"][0]["name"]).to eq("Post 2")
          expect(response.parsed_body["posts"][1]["name"]).to eq("Post 1")
        end

        context "when post has A/B test variants" do
          let!(:variant_a) { create(:post_variant, installment: post1, name: "Variant A", is_control: true, message: "Control message") }
          let!(:variant_b) { create(:post_variant, installment: post1, name: "Variant B", message: "Treatment message") }

          it "includes has_ab_test and post_variants_count in response" do
            get action, params: params
            expect(response).to have_http_status(:ok)

            post_with_ab_test = response.parsed_body["posts"].find { |p| p["name"] == "Post 1" }
            expect(post_with_ab_test["has_ab_test"]).to be true
            expect(post_with_ab_test["post_variants_count"]).to eq(2)
          end

          context "when buyer has a variant assignment" do
            let!(:assignment) { create(:variant_assignment, post_variant: variant_b, user_id: seller.id, subscription: nil) }

            it "returns variant-specific message and records exposure" do
              expect(assignment.exposed_at).to be_nil

              get action, params: params

              post_with_ab_test = response.parsed_body["posts"].find { |p| p["name"] == "Post 1" }
              expect(post_with_ab_test["message"]).to eq("Treatment message")
              expect(post_with_ab_test["assigned_variant_id"]).to eq(variant_b.external_id)

              assignment.reload
              expect(assignment.exposed_at).to be_present
            end
          end

          context "when buyer has no variant assignment" do
            it "returns base post message" do
              get action, params: params

              post_with_ab_test = response.parsed_body["posts"].find { |p| p["name"] == "Post 1" }
              expect(post_with_ab_test["assigned_variant_id"]).to be_nil
            end
          end
        end
      end

      context "when product has no posts" do
        it "returns empty array" do
          get action, params: params
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body["success"]).to be true
          expect(response.parsed_body["posts"]).to eq([])
        end
      end
    end
  end

  describe "GET 'show'" do
    let(:action) { :show }
    let!(:post) { create(:installment, :published, link: product, name: "Test Post", message: "Base message") }
    let(:params) { { link_id: product.external_id, id: post.external_id } }

    context "when logged in with public scope" do
      let(:token) { create("doorkeeper/access_token", application: app, resource_owner_id: seller.id, scopes: "view_public") }

      before do
        params.merge!(format: :json, access_token: token.token)
      end

      it "returns the post" do
        get action, params: params
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["post"]["name"]).to eq("Test Post")
      end

      context "when post has A/B test variants" do
        let!(:variant_a) { create(:post_variant, installment: post, name: "Control", is_control: true, message: "Control message") }
        let!(:variant_b) { create(:post_variant, installment: post, name: "Treatment", message: "Treatment message") }

        context "when buyer has a variant assignment" do
          let!(:assignment) { create(:variant_assignment, post_variant: variant_b, user_id: seller.id, subscription: nil) }

          it "returns variant-specific message" do
            get action, params: params
            expect(response.parsed_body["post"]["message"]).to eq("Treatment message")
            expect(response.parsed_body["post"]["assigned_variant_id"]).to eq(variant_b.external_id)
          end

          it "records exposure on the variant assignment" do
            expect(assignment.exposed_at).to be_nil

            get action, params: params

            assignment.reload
            expect(assignment.exposed_at).to be_present
          end

          it "does not update exposure if already exposed" do
            original_time = 1.day.ago
            assignment.update!(exposed_at: original_time)

            get action, params: params

            assignment.reload
            expect(assignment.exposed_at).to eq(original_time)
          end
        end

        context "when buyer has no variant assignment" do
          it "returns base post message" do
            get action, params: params
            expect(response.parsed_body["post"]["message"]).to eq("Base message")
            expect(response.parsed_body["post"]["assigned_variant_id"]).to be_nil
          end
        end
      end

      context "when post does not exist" do
        let(:params) { { link_id: product.external_id, id: "nonexistent" } }

        it "returns error" do
          get action, params: params
          expect(response.parsed_body["success"]).to be false
          expect(response.parsed_body["message"]).to eq("The post was not found.")
        end
      end
    end
  end
end
