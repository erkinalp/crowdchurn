# frozen_string_literal: true

require "spec_helper"

describe VariantAssignment do
  describe "associations" do
    it "belongs to a post_variant" do
      assignment = build(:variant_assignment)
      expect(assignment).to respond_to(:post_variant)
    end

    it "belongs to a subscription" do
      assignment = build(:variant_assignment)
      expect(assignment).to respond_to(:subscription)
    end
  end

  describe "validations" do
    it "requires assigned_at" do
      assignment = build(:variant_assignment, assigned_at: nil)
      assignment.valid?
      expect(assignment.assigned_at).to be_present
    end

    it "enforces uniqueness of subscription within post_variant scope" do
      installment = create(:installment)
      post_variant = create(:post_variant, installment: installment)
      subscription = create(:subscription)

      create(:variant_assignment, post_variant: post_variant, subscription: subscription)

      duplicate = build(:variant_assignment, post_variant: post_variant, subscription: subscription)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:subscription_id]).to include("has already been assigned to this variant")
    end

    it "allows same subscription to be assigned to different post_variants" do
      installment = create(:installment)
      post_variant1 = create(:post_variant, installment: installment, name: "Variant A")
      post_variant2 = create(:post_variant, installment: installment, name: "Variant B")
      subscription = create(:subscription)

      create(:variant_assignment, post_variant: post_variant1, subscription: subscription)

      assignment2 = build(:variant_assignment, post_variant: post_variant2, subscription: subscription)
      expect(assignment2).to be_valid
    end
  end

  describe "callbacks" do
    describe "before_validation on create" do
      it "sets assigned_at to current time if not provided" do
        assignment = build(:variant_assignment, assigned_at: nil)
        assignment.valid?
        expect(assignment.assigned_at).to be_present
      end

      it "does not override assigned_at if already set" do
        specific_time = 1.day.ago
        assignment = build(:variant_assignment, assigned_at: specific_time)
        assignment.valid?
        expect(assignment.assigned_at).to eq(specific_time)
      end
    end
  end
end
