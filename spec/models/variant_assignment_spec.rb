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

    it "belongs to a purchase" do
      assignment = build(:variant_assignment)
      expect(assignment).to respond_to(:purchase)
    end
  end

  describe "scopes" do
    let(:installment) { create(:installment) }
    let(:post_variant) { create(:post_variant, installment: installment) }

    describe ".exposed" do
      it "returns assignments with exposed_at set" do
        exposed_assignment = create(:variant_assignment, post_variant: post_variant, subscription: create(:subscription), exposed_at: Time.current)
        unexposed_assignment = create(:variant_assignment, post_variant: post_variant, subscription: create(:subscription), exposed_at: nil)

        expect(VariantAssignment.exposed).to include(exposed_assignment)
        expect(VariantAssignment.exposed).not_to include(unexposed_assignment)
      end
    end

    describe ".converted" do
      it "returns assignments with converted_at set" do
        converted_assignment = create(:variant_assignment, post_variant: post_variant, subscription: create(:subscription), converted_at: Time.current)
        unconverted_assignment = create(:variant_assignment, post_variant: post_variant, subscription: create(:subscription), converted_at: nil)

        expect(VariantAssignment.converted).to include(converted_assignment)
        expect(VariantAssignment.converted).not_to include(unconverted_assignment)
      end
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

  describe "#record_exposure!" do
    let(:installment) { create(:installment) }
    let(:post_variant) { create(:post_variant, installment: installment) }
    let(:subscription) { create(:subscription) }
    let(:assignment) { create(:variant_assignment, post_variant: post_variant, subscription: subscription) }

    it "sets exposed_at to current time" do
      expect(assignment.exposed_at).to be_nil

      freeze_time do
        assignment.record_exposure!
        expect(assignment.reload.exposed_at).to eq(Time.current)
      end
    end

    it "does not update exposed_at if already set" do
      original_time = 1.day.ago
      assignment.update!(exposed_at: original_time)

      assignment.record_exposure!
      expect(assignment.reload.exposed_at).to eq(original_time)
    end

    it "returns nil if already exposed" do
      assignment.update!(exposed_at: Time.current)
      expect(assignment.record_exposure!).to be_nil
    end
  end

  describe "#record_conversion!" do
    let(:installment) { create(:installment) }
    let(:post_variant) { create(:post_variant, installment: installment) }
    let(:subscription) { create(:subscription) }
    let(:assignment) { create(:variant_assignment, post_variant: post_variant, subscription: subscription) }
    let(:purchase) { create(:purchase) }

    it "sets converted_at and purchase_id" do
      expect(assignment.converted_at).to be_nil
      expect(assignment.purchase_id).to be_nil

      freeze_time do
        assignment.record_conversion!(purchase)
        assignment.reload
        expect(assignment.converted_at).to eq(Time.current)
        expect(assignment.purchase_id).to eq(purchase.id)
      end
    end

    it "does not update if already converted" do
      original_time = 1.day.ago
      original_purchase = create(:purchase)
      assignment.update!(converted_at: original_time, purchase_id: original_purchase.id)

      new_purchase = create(:purchase)
      assignment.record_conversion!(new_purchase)
      assignment.reload

      expect(assignment.converted_at).to eq(original_time)
      expect(assignment.purchase_id).to eq(original_purchase.id)
    end
  end

  describe "#exposed?" do
    let(:installment) { create(:installment) }
    let(:post_variant) { create(:post_variant, installment: installment) }
    let(:subscription) { create(:subscription) }

    it "returns true if exposed_at is set" do
      assignment = create(:variant_assignment, post_variant: post_variant, subscription: subscription, exposed_at: Time.current)
      expect(assignment.exposed?).to be true
    end

    it "returns false if exposed_at is nil" do
      assignment = create(:variant_assignment, post_variant: post_variant, subscription: subscription, exposed_at: nil)
      expect(assignment.exposed?).to be false
    end
  end

  describe "#converted?" do
    let(:installment) { create(:installment) }
    let(:post_variant) { create(:post_variant, installment: installment) }
    let(:subscription) { create(:subscription) }

    it "returns true if converted_at is set" do
      assignment = create(:variant_assignment, post_variant: post_variant, subscription: subscription, converted_at: Time.current)
      expect(assignment.converted?).to be true
    end

    it "returns false if converted_at is nil" do
      assignment = create(:variant_assignment, post_variant: post_variant, subscription: subscription, converted_at: nil)
      expect(assignment.converted?).to be false
    end
  end

  describe ".find_assignment_for_buyer" do
    let(:installment) { create(:installment) }
    let(:post_variant) { create(:post_variant, installment: installment) }
    let(:user) { create(:user) }
    let(:buyer_cookie) { SecureRandom.uuid }

    before do
      create(:post_variant, installment: installment, name: "Control")
    end

    it "finds assignment by user_id" do
      assignment = create(:variant_assignment, post_variant: post_variant, user_id: user.id)

      found = VariantAssignment.find_assignment_for_buyer(installment: installment, user: user)
      expect(found).to eq(assignment)
    end

    it "finds assignment by buyer_cookie" do
      assignment = create(:variant_assignment, post_variant: post_variant, buyer_cookie: buyer_cookie)

      found = VariantAssignment.find_assignment_for_buyer(installment: installment, buyer_cookie: buyer_cookie)
      expect(found).to eq(assignment)
    end

    it "returns nil if no assignment exists" do
      found = VariantAssignment.find_assignment_for_buyer(installment: installment, user: user)
      expect(found).to be_nil
    end

    it "returns nil if no identity provided" do
      found = VariantAssignment.find_assignment_for_buyer(installment: installment)
      expect(found).to be_nil
    end
  end
end
