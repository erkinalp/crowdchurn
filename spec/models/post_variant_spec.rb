# frozen_string_literal: true

require "spec_helper"

describe PostVariant do
  describe "associations" do
    it "belongs to an installment" do
      post_variant = build(:post_variant)
      expect(post_variant).to respond_to(:installment)
    end

    it "has many variant_distribution_rules" do
      post_variant = build(:post_variant)
      expect(post_variant).to respond_to(:variant_distribution_rules)
    end

    it "has many variant_assignments" do
      post_variant = build(:post_variant)
      expect(post_variant).to respond_to(:variant_assignments)
    end
  end

  describe "validations" do
    it "requires a name" do
      post_variant = build(:post_variant, name: nil)
      expect(post_variant).not_to be_valid
      expect(post_variant.errors[:name]).to include("can't be blank")
    end

    it "requires a message" do
      post_variant = build(:post_variant, message: nil)
      expect(post_variant).not_to be_valid
      expect(post_variant.errors[:message]).to include("can't be blank")
    end

    it "is valid with all required attributes" do
      post_variant = build(:post_variant)
      expect(post_variant).to be_valid
    end
  end

  describe "scopes" do
    describe ".control" do
      it "returns only control variants" do
        installment = create(:installment)
        control_variant = create(:post_variant, installment: installment, is_control: true)
        create(:post_variant, installment: installment, is_control: false)

        expect(described_class.control).to eq([control_variant])
      end
    end
  end

  describe "#control?" do
    it "returns true when is_control is true" do
      post_variant = build(:post_variant, is_control: true)
      expect(post_variant.control?).to be true
    end

    it "returns false when is_control is false" do
      post_variant = build(:post_variant, is_control: false)
      expect(post_variant.control?).to be false
    end
  end
end
