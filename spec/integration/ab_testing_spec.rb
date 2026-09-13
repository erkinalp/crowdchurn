# frozen_string_literal: true

require "spec_helper"

describe "A/B Testing Integration" do
  let(:creator) { create(:named_seller) }
  let(:product) { create(:subscription_product, user: creator) }
  let(:variant_category) { create(:variant_category, link: product) }
  let(:tier_a) { create(:variant, variant_category: variant_category, name: "Tier A") }
  let(:tier_b) { create(:variant, variant_category: variant_category, name: "Tier B") }

  describe "End-to-End Workflow" do
    context "creator creates post with A/B variants" do
      let(:post) { create(:published_installment, link: product, seller: creator) }

      before do
        @variant_a = create(:post_variant, installment: post, name: "Variant A", message: "Content for Variant A", is_control: true)
        @variant_b = create(:post_variant, installment: post, name: "Variant B", message: "Content for Variant B", is_control: false)
      end

      it "creates post variants successfully" do
        expect(post.post_variants.count).to eq(2)
        expect(post.has_ab_test?).to be true
      end

      context "with distribution rules configured" do
        before do
          create(:variant_distribution_rule, post_variant: @variant_a, base_variant: tier_a, distribution_type: :percentage, distribution_value: 50)
          create(:variant_distribution_rule, post_variant: @variant_b, base_variant: tier_a, distribution_type: :percentage, distribution_value: 50)
          create(:variant_distribution_rule, post_variant: @variant_a, base_variant: tier_b, distribution_type: :unlimited)
        end

        it "configures distribution rules correctly" do
          expect(@variant_a.variant_distribution_rules.count).to eq(2)
          expect(@variant_b.variant_distribution_rules.count).to eq(1)
        end

        context "when subscriber views post" do
          let(:subscription_a) { create(:subscription, link: product) }
          let(:purchase_a) do
            create(:membership_purchase,
                   link: product,
                   subscription: subscription_a,
                   is_original_subscription_purchase: true,
                   variant_attributes: [tier_a])
          end

          before do
            purchase_a
          end

          it "assigns and serves correct variant to subscriber" do
            assigned_variant = post.variant_for_subscription(subscription_a)
            expect(assigned_variant).to be_present
            expect([post.post_variants.first, post.post_variants.second]).to include(assigned_variant)
          end

          it "persists variant assignment for same subscriber" do
            first_assignment = post.variant_for_subscription(subscription_a)
            second_assignment = post.variant_for_subscription(subscription_a)

            expect(first_assignment).to eq(second_assignment)
            expect(VariantAssignment.where(subscription: subscription_a, post_variant: post.post_variants).count).to eq(1)
          end
        end
      end
    end
  end

  describe "Variant Assignment Persistence" do
    let(:post) { create(:published_installment, link: product, seller: creator) }
    let(:variant_a) { create(:post_variant, installment: post, name: "Variant A", is_control: true) }
    let(:variant_b) { create(:post_variant, installment: post, name: "Variant B") }
    let(:subscription) { create(:subscription, link: product) }

    before do
      create(:variant_distribution_rule, post_variant: variant_a, base_variant: tier_a, distribution_type: :unlimited)
      create(:variant_distribution_rule, post_variant: variant_b, base_variant: tier_a, distribution_type: :unlimited)
      create(:membership_purchase,
             link: product,
             subscription: subscription,
             is_original_subscription_purchase: true,
             variant_attributes: [tier_a])
    end

    it "same subscriber always sees same variant across multiple requests" do
      first_variant = post.variant_for_subscription(subscription)

      10.times do
        expect(post.variant_for_subscription(subscription)).to eq(first_variant)
      end
    end

    it "creates only one assignment per subscription per post" do
      5.times { post.variant_for_subscription(subscription) }

      expect(VariantAssignment.where(subscription: subscription).count).to eq(1)
    end
  end

  describe "Distribution Algorithm Accuracy" do
    let(:post) { create(:published_installment, link: product, seller: creator) }
    let(:variant_a) { create(:post_variant, installment: post, name: "Variant A", is_control: true) }
    let(:variant_b) { create(:post_variant, installment: post, name: "Variant B") }

    context "with percentage-based distribution" do
      before do
        create(:variant_distribution_rule, post_variant: variant_a, base_variant: tier_a, distribution_type: :percentage, distribution_value: 50)
        create(:variant_distribution_rule, post_variant: variant_b, base_variant: tier_a, distribution_type: :percentage, distribution_value: 50)
      end

      it "distributes variants according to percentages" do
        subscriptions = 20.times.map do
          subscription = create(:subscription, link: product)
          create(:membership_purchase,
                 link: product,
                 subscription: subscription,
                 is_original_subscription_purchase: true,
                 variant_attributes: [tier_a])
          subscription
        end

        variant_a_count = 0
        variant_b_count = 0

        subscriptions.each do |subscription|
          assigned = post.variant_for_subscription(subscription)
          if assigned == variant_a
            variant_a_count += 1
          elsif assigned == variant_b
            variant_b_count += 1
          end
        end

        expect(variant_a_count + variant_b_count).to eq(20)
        expect(variant_a_count).to be > 0
        expect(variant_b_count).to be > 0
      end
    end

    context "with count-based distribution" do
      before do
        create(:variant_distribution_rule, post_variant: variant_a, base_variant: tier_a, distribution_type: :count, distribution_value: 5)
        create(:variant_distribution_rule, post_variant: variant_b, base_variant: tier_a, distribution_type: :unlimited)
      end

      it "respects count limits" do
        subscriptions = 10.times.map do
          subscription = create(:subscription, link: product)
          create(:membership_purchase,
                 link: product,
                 subscription: subscription,
                 is_original_subscription_purchase: true,
                 variant_attributes: [tier_a])
          subscription
        end

        subscriptions.each do |subscription|
          post.variant_for_subscription(subscription)
        end

        variant_a_assignments = VariantAssignment.where(post_variant: variant_a).count
        expect(variant_a_assignments).to be <= 5
      end
    end

    context "with unlimited distribution" do
      before do
        create(:variant_distribution_rule, post_variant: variant_a, base_variant: tier_a, distribution_type: :unlimited)
      end

      it "assigns all subscribers to the unlimited variant" do
        subscriptions = 10.times.map do
          subscription = create(:subscription, link: product)
          create(:membership_purchase,
                 link: product,
                 subscription: subscription,
                 is_original_subscription_purchase: true,
                 variant_attributes: [tier_a])
          subscription
        end

        subscriptions.each do |subscription|
          assigned = post.variant_for_subscription(subscription)
          expect(assigned).to eq(variant_a)
        end
      end
    end
  end

  describe "Variant-Scoped Comments" do
    let(:post) { create(:published_installment, link: product, seller: creator, allow_comments: true) }
    let(:variant_a) { create(:post_variant, installment: post, name: "Variant A", is_control: true) }
    let(:variant_b) { create(:post_variant, installment: post, name: "Variant B") }

    let(:subscription_a1) { create(:subscription, link: product) }
    let(:subscription_a2) { create(:subscription, link: product) }
    let(:subscription_b) { create(:subscription, link: product) }

    before do
      create(:variant_distribution_rule, post_variant: variant_a, base_variant: tier_a, distribution_type: :unlimited)
      create(:variant_distribution_rule, post_variant: variant_b, base_variant: tier_b, distribution_type: :unlimited)

      @purchase_a1 = create(:membership_purchase,
                            link: product,
                            subscription: subscription_a1,
                            is_original_subscription_purchase: true,
                            variant_attributes: [tier_a])
      @purchase_a2 = create(:membership_purchase,
                            link: product,
                            subscription: subscription_a2,
                            is_original_subscription_purchase: true,
                            variant_attributes: [tier_a])
      @purchase_b = create(:membership_purchase,
                           link: product,
                           subscription: subscription_b,
                           is_original_subscription_purchase: true,
                           variant_attributes: [tier_b])

      post.variant_for_subscription(subscription_a1)
      post.variant_for_subscription(subscription_a2)
      post.variant_for_subscription(subscription_b)
    end

    context "subscriber comments on post" do
      let!(:comment_from_a1) do
        create(:comment,
               commentable: post,
               post_variant: variant_a,
               content: "Comment from subscriber A1",
               purchase: @purchase_a1)
      end

      let!(:comment_from_b) do
        create(:comment,
               commentable: post,
               post_variant: variant_b,
               content: "Comment from subscriber B",
               purchase: @purchase_b)
      end

      it "scopes comment to subscriber's assigned variant" do
        expect(comment_from_a1.post_variant).to eq(variant_a)
        expect(comment_from_b.post_variant).to eq(variant_b)
      end

      it "allows subscribers with same variant to see each other's comments" do
        visible_to_a2 = post.comments.visible_to_variant(variant_a.id)
        expect(visible_to_a2).to include(comment_from_a1)
      end

      it "prevents subscribers with different variants from seeing each other's comments" do
        visible_to_b = post.comments.visible_to_variant(variant_b.id)
        expect(visible_to_b).not_to include(comment_from_a1)

        visible_to_a = post.comments.visible_to_variant(variant_a.id)
        expect(visible_to_a).not_to include(comment_from_b)
      end

      it "allows creator to see all comments" do
        all_comments = post.comments.alive
        expect(all_comments).to include(comment_from_a1, comment_from_b)
      end

      it "allows creator to filter comments by variant" do
        variant_a_comments = post.comments.for_variant(variant_a.id)
        expect(variant_a_comments).to include(comment_from_a1)
        expect(variant_a_comments).not_to include(comment_from_b)

        variant_b_comments = post.comments.for_variant(variant_b.id)
        expect(variant_b_comments).to include(comment_from_b)
        expect(variant_b_comments).not_to include(comment_from_a1)
      end
    end

    context "unscoped comments (no variant)" do
      let!(:unscoped_comment) do
        create(:comment,
               commentable: post,
               post_variant: nil,
               content: "Unscoped comment visible to all")
      end

      it "are visible to all subscribers regardless of variant" do
        expect(post.comments.visible_to_variant(variant_a.id)).to include(unscoped_comment)
        expect(post.comments.visible_to_variant(variant_b.id)).to include(unscoped_comment)
      end

      it "are included in unscoped_variant scope" do
        expect(post.comments.unscoped_variant).to include(unscoped_comment)
      end
    end
  end

  describe "Subscription Access Tests" do
    let(:post) { create(:published_installment, link: product, seller: creator) }
    let(:variant_a) { create(:post_variant, installment: post, name: "Variant A", is_control: true) }
    let(:variant_b) { create(:post_variant, installment: post, name: "Variant B") }

    context "tier-specific distribution rules" do
      before do
        create(:variant_distribution_rule, post_variant: variant_a, base_variant: tier_a, distribution_type: :unlimited)
        create(:variant_distribution_rule, post_variant: variant_b, base_variant: tier_b, distribution_type: :unlimited)
      end

      it "serves correct variant based on subscription tier" do
        subscription_tier_a = create(:subscription, link: product)
        create(:membership_purchase,
               link: product,
               subscription: subscription_tier_a,
               is_original_subscription_purchase: true,
               variant_attributes: [tier_a])

        subscription_tier_b = create(:subscription, link: product)
        create(:membership_purchase,
               link: product,
               subscription: subscription_tier_b,
               is_original_subscription_purchase: true,
               variant_attributes: [tier_b])

        expect(post.variant_for_subscription(subscription_tier_a)).to eq(variant_a)
        expect(post.variant_for_subscription(subscription_tier_b)).to eq(variant_b)
      end
    end

    context "fallback behavior when no rules match tier" do
      before do
        create(:variant_distribution_rule, post_variant: variant_a, base_variant: tier_a, distribution_type: :unlimited)
      end

      it "falls back to first available rule or control variant" do
        subscription_tier_b = create(:subscription, link: product)
        create(:membership_purchase,
               link: product,
               subscription: subscription_tier_b,
               is_original_subscription_purchase: true,
               variant_attributes: [tier_b])

        assigned = post.variant_for_subscription(subscription_tier_b)
        expect(assigned).to be_present
      end
    end
  end

  describe "Backward Compatibility" do
    context "posts without A/B variants" do
      let(:regular_post) { create(:published_installment, link: product, seller: creator) }
      let(:subscription) { create(:subscription, link: product) }

      before do
        create(:membership_purchase,
               link: product,
               subscription: subscription,
               is_original_subscription_purchase: true,
               variant_attributes: [tier_a])
      end

      it "returns nil for variant_for_subscription" do
        expect(regular_post.variant_for_subscription(subscription)).to be_nil
      end

      it "has_ab_test? returns false" do
        expect(regular_post.has_ab_test?).to be false
      end

      it "comments work normally without variant scoping" do
        comment = create(:comment, commentable: regular_post, content: "Regular comment")
        expect(comment.post_variant).to be_nil
        expect(regular_post.comments.unscoped_variant).to include(comment)
      end
    end

    context "posts with single variant (not A/B test)" do
      let(:single_variant_post) { create(:published_installment, link: product, seller: creator) }

      before do
        create(:post_variant, installment: single_variant_post, name: "Only Variant")
      end

      it "has_ab_test? returns false for single variant" do
        expect(single_variant_post.has_ab_test?).to be false
      end
    end
  end

  describe "Edge Cases" do
    context "post with variants but no distribution rules" do
      let(:post) { create(:published_installment, link: product, seller: creator) }
      let!(:variant_a) { create(:post_variant, installment: post, name: "Variant A", is_control: true) }
      let!(:variant_b) { create(:post_variant, installment: post, name: "Variant B") }

      it "falls back to control variant or first variant" do
        subscription = create(:subscription, link: product)
        create(:membership_purchase,
               link: product,
               subscription: subscription,
               is_original_subscription_purchase: true,
               variant_attributes: [tier_a])

        assigned = post.variant_for_subscription(subscription)
        expect(assigned).to eq(variant_a)
      end
    end

    context "variant deletion when assignments exist" do
      let(:post) { create(:published_installment, link: product, seller: creator) }
      let(:variant_a) { create(:post_variant, installment: post, name: "Variant A", is_control: true) }
      let(:subscription) { create(:subscription, link: product) }

      before do
        create(:variant_distribution_rule, post_variant: variant_a, base_variant: tier_a, distribution_type: :unlimited)
        create(:membership_purchase,
               link: product,
               subscription: subscription,
               is_original_subscription_purchase: true,
               variant_attributes: [tier_a])
        post.variant_for_subscription(subscription)
      end

      it "handles variant deletion gracefully" do
        expect(VariantAssignment.where(post_variant: variant_a).count).to eq(1)

        variant_a.destroy

        expect(VariantAssignment.where(post_variant_id: variant_a.id).count).to eq(0)
      end
    end

    context "comment on A/B post before variant assignment exists" do
      let(:post) { create(:published_installment, link: product, seller: creator, allow_comments: true) }
      let!(:variant_a) { create(:post_variant, installment: post, name: "Variant A", is_control: true) }
      let(:subscription) { create(:subscription, link: product) }

      before do
        @purchase = create(:membership_purchase,
                           link: product,
                           subscription: subscription,
                           is_original_subscription_purchase: true,
                           variant_attributes: [tier_a])
      end

      it "creates comment without variant assignment" do
        comment = create(:comment,
                         commentable: post,
                         post_variant: nil,
                         content: "Comment before assignment",
                         purchase: @purchase)

        expect(comment.post_variant).to be_nil
        expect(post.comments.unscoped_variant).to include(comment)
      end
    end

    context "concurrent variant assignment requests" do
      let(:post) { create(:published_installment, link: product, seller: creator) }
      let(:variant_a) { create(:post_variant, installment: post, name: "Variant A", is_control: true) }
      let(:subscription) { create(:subscription, link: product) }

      before do
        create(:variant_distribution_rule, post_variant: variant_a, base_variant: tier_a, distribution_type: :unlimited)
        create(:membership_purchase,
               link: product,
               subscription: subscription,
               is_original_subscription_purchase: true,
               variant_attributes: [tier_a])
      end

      it "handles concurrent requests without creating duplicate assignments" do
        threads = 5.times.map do
          Thread.new do
            post.variant_for_subscription(subscription)
          end
        end

        threads.each(&:join)

        expect(VariantAssignment.where(subscription: subscription, post_variant: post.post_variants).count).to be <= 1
      end
    end
  end

  describe "Performance Verification" do
    context "N+1 query prevention in variant selection" do
      let(:post) { create(:published_installment, link: product, seller: creator) }
      let(:variant_a) { create(:post_variant, installment: post, name: "Variant A", is_control: true) }

      before do
        create(:variant_distribution_rule, post_variant: variant_a, base_variant: tier_a, distribution_type: :unlimited)
      end

      it "does not generate N+1 queries when selecting variants for multiple subscriptions" do
        subscriptions = 5.times.map do
          subscription = create(:subscription, link: product)
          create(:membership_purchase,
                 link: product,
                 subscription: subscription,
                 is_original_subscription_purchase: true,
                 variant_attributes: [tier_a])
          subscription
        end

        expect do
          subscriptions.each do |subscription|
            post.variant_for_subscription(subscription)
          end
        end.to make_database_queries(count: 1..50)
      end
    end

    context "N+1 query prevention in comment filtering" do
      let(:post) { create(:published_installment, link: product, seller: creator, allow_comments: true) }
      let(:variant_a) { create(:post_variant, installment: post, name: "Variant A", is_control: true) }

      before do
        10.times do
          create(:comment, commentable: post, post_variant: variant_a, content: "Test comment")
        end
      end

      it "does not generate N+1 queries when filtering comments by variant" do
        expect do
          post.comments.for_variant(variant_a.id).to_a
        end.to make_database_queries(count: 1..5)
      end

      it "does not generate N+1 queries when filtering visible comments" do
        expect do
          post.comments.visible_to_variant(variant_a.id).to_a
        end.to make_database_queries(count: 1..5)
      end
    end
  end
end
