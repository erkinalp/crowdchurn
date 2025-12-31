# frozen_string_literal: true

require "spec_helper"

describe Comment do
  describe "validations" do
    describe "content length" do
      context "when content is within the configured character limit" do
        subject(:comment) { build(:comment, commentable: create(:published_installment), content: "a" * 10_000) }

        it "marks the comment as valid" do
          expect(comment).to be_valid
        end
      end

      context "when content is bigger than the configured character limit" do
        subject(:comment) { build(:comment, commentable: create(:published_installment), content: "a" * 10_001) }

        it "marks the comment as invalid" do
          expect(comment).to be_invalid
          expect(comment.errors.full_messages).to match_array(["Content is too long (maximum is 10000 characters)"])
        end
      end
    end

    describe "content_cannot_contain_adult_keywords" do
      context "when content contains an adult keyword" do
        context "when the author is not a team member" do
          subject(:comment) { build(:comment, commentable: create(:published_installment), content: "nsfw content") }

          it "marks the comment as invalid" do
            expect(comment).to be_invalid
            expect(comment.errors.full_messages).to match_array(["Adult keywords are not allowed"])
          end
        end

        context "when the author is a team member" do
          subject(:comment) { build(:comment, commentable: create(:published_installment), content: "nsfw content", author: create(:user, is_team_member: true)) }

          it "marks the comment as valid" do
            expect(comment).to be_valid
          end
        end

        context "when author name is iffy" do
          subject(:comment) { build(:comment, commentable: create(:published_installment), author: nil, content: "nsfw content", author_name: "iffy") }

          it "marks the comment as valid" do
            expect(comment).to be_valid
          end
        end
      end

      context "when content does not contain adult keywords" do
        subject(:comment) { build(:comment, commentable: create(:published_installment)) }

        it "marks the comment as valid" do
          expect(comment).to be_valid
        end
      end
    end

    describe "depth numericality" do
      let(:commentable) { create(:published_installment) }
      let(:root_comment) { create(:comment, commentable:) }
      let(:reply1) { create(:comment, parent: root_comment, commentable:) }
      let(:reply_at_depth_2) { create(:comment, parent: reply1, commentable:) }
      let(:reply_at_depth_3) { create(:comment, parent: reply_at_depth_2, commentable:) }
      let(:reply_at_depth_4) { create(:comment, parent: reply_at_depth_3, commentable:) }

      context "when a comment exceeds maximum allowed depth" do
        subject(:reply_at_depth_5) { build(:comment, parent: reply_at_depth_4, commentable:) }

        it "marks the comment as invalid" do
          expect(reply_at_depth_5).to be_invalid
          expect(reply_at_depth_5.errors.full_messages).to match_array(["Depth must be less than or equal to 4"])
        end
      end

      context "when depth is set manually" do
        subject(:comment) { build(:comment, commentable:, parent: root_comment, ancestry_depth: 3) }

        it "marks the comment as valid and sets the depth according to its actual position in its ancestry tree" do
          expect(comment).to be_valid
          expect(comment.depth).to eq(1)
        end
      end
    end
  end

  describe "callbacks" do
    describe "before_save" do
      describe "#trim_extra_newlines" do
        subject(:comment) { build(:comment, commentable: create(:published_installment)) }

        it "trims unnecessary additional newlines" do
          comment.content = "\n       Here are things -\n\n1. One\n2. Two\n\t2.1 Two.One\n\t\t2.1.1 Two.One.One\n\t\t2.1.2 Two.One.Two\n\t\t\t2.1.2.1 Two.One.Two.One\n\t2.2 Two.Two\n3. Three\n\n\n\n\nWhat do you think?\n\n   "

          expect do
            comment.save!
          end.to change { comment.content }.to("Here are things -\n\n1. One\n2. Two\n\t2.1 Two.One\n\t\t2.1.1 Two.One.One\n\t\t2.1.2 Two.One.Two\n\t\t\t2.1.2.1 Two.One.Two.One\n\t2.2 Two.Two\n3. Three\n\nWhat do you think?")
        end
      end
    end

    describe "after_commit" do
      describe "#notify_seller_of_new_comment" do
        let(:seller) { create(:named_seller) }
        let(:commentable) { create(:published_installment, seller:) }
        let(:comment) { build(:comment, commentable:, comment_type: Comment::COMMENT_TYPE_USER_SUBMITTED) }

        context "when a new comment is added" do
          context "when it is not a user submitted comment" do
            before do
              comment.comment_type = :flagged
            end

            it "does not send a notification to the seller" do
              expect do
                comment.save!
              end.to_not have_enqueued_mail(CommentMailer, :notify_seller_of_new_comment)
            end
          end

          context "when it is not a root comment" do
            before do
              comment.parent = create(:comment, commentable:)
            end

            it "does not send a notification to the seller" do
              expect do
                comment.save!
              end.to_not have_enqueued_mail(CommentMailer, :notify_seller_of_new_comment)
            end
          end

          context "when it is authored by the seller" do
            before do
              comment.author = seller
            end

            it "does not send a notification to the seller" do
              expect do
                comment.save!
              end.to_not have_enqueued_mail(CommentMailer, :notify_seller_of_new_comment)
            end
          end

          context "when the seller has opted out of comments email notifications" do
            before do
              seller.update!(disable_comments_email: true)
            end

            it "does not send a notification to the seller" do
              expect do
                comment.save!
              end.to_not have_enqueued_mail(CommentMailer, :notify_seller_of_new_comment)
            end
          end

          it "emails the seller" do
            expect do
              comment.save!
            end.to have_enqueued_mail(CommentMailer, :notify_seller_of_new_comment)
          end
        end

        context "when a comment gets updated" do
          let(:comment) { create(:comment, commentable:) }

          it "does not send a notification to the seller" do
            comment.update!(content: "new content")
          end
        end
      end
    end
  end

  describe "#mark_subtree_deleted!" do
    let(:commentable) { create(:published_installment) }
    let(:root_comment) { create(:comment, commentable:) }
    let!(:reply1) { create(:comment, parent: root_comment, commentable:) }
    let!(:reply2) { create(:comment, parent: root_comment, commentable:) }
    let!(:reply_at_depth_2) { create(:comment, parent: reply1, commentable:) }
    let!(:reply_at_depth_3) { create(:comment, parent: reply_at_depth_2, commentable:, deleted_at: 1.minute.ago) }
    let!(:reply_at_depth_4) { create(:comment, parent: reply_at_depth_3, commentable:) }

    it "soft deletes the comment along with its descendants" do
      expect do
        expect do
          expect do
            expect do
              reply1.mark_subtree_deleted!
            end.to change { reply1.reload.alive? }.from(true).to(false)
            .and change { reply_at_depth_2.reload.alive? }.from(true).to(false)
            .and change { reply_at_depth_4.reload.alive? }.from(true).to(false)
          end.to_not change { root_comment.reload.alive? }
        end.to_not change { reply2.reload.alive? }
      end.to_not change { reply_at_depth_3.reload.alive? }

      expect(root_comment.was_alive_before_marking_subtree_deleted).to be_nil
      expect(reply1.was_alive_before_marking_subtree_deleted).to be_nil
      expect(reply2.was_alive_before_marking_subtree_deleted).to be_nil
      expect(reply_at_depth_2.was_alive_before_marking_subtree_deleted).to eq(true)
      expect(reply_at_depth_3.was_alive_before_marking_subtree_deleted).to be_nil
      expect(reply_at_depth_4.was_alive_before_marking_subtree_deleted).to eq(true)
    end
  end

  describe "#mark_subtree_undeleted!" do
    let(:commentable) { create(:published_installment) }
    let(:root_comment) { create(:comment, commentable:) }
    let!(:reply1) { create(:comment, parent: root_comment, commentable:) }
    let!(:reply2) { create(:comment, parent: root_comment, commentable:) }
    let!(:reply_at_depth_2) { create(:comment, parent: reply1, commentable:) }
    let!(:reply_at_depth_3) { create(:comment, parent: reply_at_depth_2, commentable:) }

    before do
      reply1.mark_subtree_deleted!
    end

    it "marks the comment and its descendants undeleted" do
      expect do
        expect do
          expect do
            reply1.mark_subtree_undeleted!
          end.to change { reply1.reload.alive? }.from(false).to(true)
          .and change { reply_at_depth_2.reload.alive? }.from(false).to(true)
          .and change { reply_at_depth_3.reload.alive? }.from(false).to(true)
        end.to_not change { root_comment.reload.alive? }
      end.to_not change { reply2.reload.alive? }

      expect(Comment.all.map(&:was_alive_before_marking_subtree_deleted).uniq).to match_array([nil])
    end
  end

  describe "Variant Scoping" do
    let(:creator) { create(:named_seller) }
    let(:product) { create(:subscription_product, user: creator) }
    let(:post) { create(:published_installment, link: product, seller: creator, allow_comments: true) }
    let(:variant_a) { create(:post_variant, installment: post, name: "Variant A", is_control: true) }
    let(:variant_b) { create(:post_variant, installment: post, name: "Variant B") }

    describe "associations" do
      it "belongs to post_variant" do
        comment = build(:comment, commentable: post, post_variant: variant_a)
        expect(comment).to respond_to(:post_variant)
        expect(comment.post_variant).to eq(variant_a)
      end

      it "allows nil post_variant for unscoped comments" do
        comment = build(:comment, commentable: post, post_variant: nil)
        expect(comment).to be_valid
        expect(comment.post_variant).to be_nil
      end
    end

    describe ".for_variant scope" do
      let!(:comment_variant_a) { create(:comment, commentable: post, post_variant: variant_a, content: "Comment for Variant A") }
      let!(:comment_variant_b) { create(:comment, commentable: post, post_variant: variant_b, content: "Comment for Variant B") }
      let!(:unscoped_comment) { create(:comment, commentable: post, post_variant: nil, content: "Unscoped comment") }

      it "returns only comments for the specified variant" do
        result = post.comments.for_variant(variant_a.id)
        expect(result).to include(comment_variant_a)
        expect(result).not_to include(comment_variant_b)
        expect(result).not_to include(unscoped_comment)
      end

      it "returns empty when no comments exist for variant" do
        variant_c = create(:post_variant, installment: post, name: "Variant C")
        result = post.comments.for_variant(variant_c.id)
        expect(result).to be_empty
      end
    end

    describe ".visible_to_variant scope" do
      let!(:comment_variant_a) { create(:comment, commentable: post, post_variant: variant_a, content: "Comment for Variant A") }
      let!(:comment_variant_b) { create(:comment, commentable: post, post_variant: variant_b, content: "Comment for Variant B") }
      let!(:unscoped_comment) { create(:comment, commentable: post, post_variant: nil, content: "Unscoped comment") }

      it "returns comments for the specified variant and unscoped comments" do
        result = post.comments.visible_to_variant(variant_a.id)
        expect(result).to include(comment_variant_a)
        expect(result).to include(unscoped_comment)
        expect(result).not_to include(comment_variant_b)
      end

      it "returns only unscoped comments when variant has no specific comments" do
        variant_c = create(:post_variant, installment: post, name: "Variant C")
        result = post.comments.visible_to_variant(variant_c.id)
        expect(result).to include(unscoped_comment)
        expect(result).not_to include(comment_variant_a)
        expect(result).not_to include(comment_variant_b)
      end
    end

    describe ".unscoped_variant scope" do
      let!(:comment_variant_a) { create(:comment, commentable: post, post_variant: variant_a, content: "Comment for Variant A") }
      let!(:unscoped_comment) { create(:comment, commentable: post, post_variant: nil, content: "Unscoped comment") }

      it "returns only comments without a variant" do
        result = post.comments.unscoped_variant
        expect(result).to include(unscoped_comment)
        expect(result).not_to include(comment_variant_a)
      end
    end

    describe "comment visibility rules" do
      let(:variant_category) { create(:variant_category, link: product) }
      let(:tier_a) { create(:variant, variant_category: variant_category, name: "Tier A") }
      let(:tier_b) { create(:variant, variant_category: variant_category, name: "Tier B") }

      let(:subscription_a1) { create(:subscription, link: product) }
      let(:subscription_a2) { create(:subscription, link: product) }
      let(:subscription_b) { create(:subscription, link: product) }

      before do
        create(:membership_purchase,
               link: product,
               subscription: subscription_a1,
               is_original_subscription_purchase: true,
               variant_attributes: [tier_a])
        create(:membership_purchase,
               link: product,
               subscription: subscription_a2,
               is_original_subscription_purchase: true,
               variant_attributes: [tier_a])
        create(:membership_purchase,
               link: product,
               subscription: subscription_b,
               is_original_subscription_purchase: true,
               variant_attributes: [tier_b])
      end

      context "subscribers with same variant" do
        let!(:comment_from_a1) { create(:comment, commentable: post, post_variant: variant_a, content: "From subscriber A1") }

        it "can see each other's comments" do
          visible_to_a2 = post.comments.visible_to_variant(variant_a.id)
          expect(visible_to_a2).to include(comment_from_a1)
        end
      end

      context "subscribers with different variants" do
        let!(:comment_from_a) { create(:comment, commentable: post, post_variant: variant_a, content: "From Variant A subscriber") }
        let!(:comment_from_b) { create(:comment, commentable: post, post_variant: variant_b, content: "From Variant B subscriber") }

        it "cannot see each other's variant-scoped comments" do
          visible_to_a = post.comments.visible_to_variant(variant_a.id)
          visible_to_b = post.comments.visible_to_variant(variant_b.id)

          expect(visible_to_a).to include(comment_from_a)
          expect(visible_to_a).not_to include(comment_from_b)

          expect(visible_to_b).to include(comment_from_b)
          expect(visible_to_b).not_to include(comment_from_a)
        end
      end

      context "creator viewing comments" do
        let!(:comment_variant_a) { create(:comment, commentable: post, post_variant: variant_a, content: "Variant A comment") }
        let!(:comment_variant_b) { create(:comment, commentable: post, post_variant: variant_b, content: "Variant B comment") }
        let!(:unscoped_comment) { create(:comment, commentable: post, post_variant: nil, content: "Unscoped comment") }

        it "can see all comments regardless of variant" do
          all_comments = post.comments.alive
          expect(all_comments).to include(comment_variant_a, comment_variant_b, unscoped_comment)
        end

        it "can filter comments by specific variant" do
          variant_a_comments = post.comments.for_variant(variant_a.id)
          expect(variant_a_comments).to include(comment_variant_a)
          expect(variant_a_comments).not_to include(comment_variant_b, unscoped_comment)
        end
      end
    end

    describe "backward compatibility" do
      context "posts without A/B variants" do
        let(:regular_post) { create(:published_installment, link: product, seller: creator, allow_comments: true) }
        let!(:regular_comment) { create(:comment, commentable: regular_post, post_variant: nil, content: "Regular comment") }

        it "comments work normally without variant scoping" do
          expect(regular_comment.post_variant).to be_nil
          expect(regular_post.comments.unscoped_variant).to include(regular_comment)
        end

        it "visible_to_variant returns all comments when passed nil" do
          result = regular_post.comments.visible_to_variant(nil)
          expect(result).to include(regular_comment)
        end
      end
    end
  end
end
