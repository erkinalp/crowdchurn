# frozen_string_literal: true

require "spec_helper"

describe VariantDistributionRule do
  describe "associations" do
    it "belongs to a post_variant" do
      rule = build(:variant_distribution_rule)
      expect(rule).to respond_to(:post_variant)
    end

    it "belongs to a base_variant" do
      rule = build(:variant_distribution_rule)
      expect(rule).to respond_to(:base_variant)
    end
  end

  describe "validations" do
    it "requires distribution_type" do
      rule = build(:variant_distribution_rule, distribution_type: nil)
      expect(rule).not_to be_valid
    end

    context "when distribution_type is percentage" do
      it "requires distribution_value" do
        rule = build(:variant_distribution_rule, distribution_type: :percentage, distribution_value: nil)
        expect(rule).not_to be_valid
        expect(rule.errors[:distribution_value]).to include("can't be blank")
      end

      it "requires distribution_value to be between 1 and 100" do
        rule = build(:variant_distribution_rule, distribution_type: :percentage, distribution_value: 0)
        expect(rule).not_to be_valid

        rule = build(:variant_distribution_rule, distribution_type: :percentage, distribution_value: 101)
        expect(rule).not_to be_valid

        rule = build(:variant_distribution_rule, distribution_type: :percentage, distribution_value: 50)
        expect(rule).to be_valid
      end
    end

    context "when distribution_type is count" do
      it "requires distribution_value" do
        rule = build(:variant_distribution_rule, distribution_type: :count, distribution_value: nil)
        expect(rule).not_to be_valid
        expect(rule.errors[:distribution_value]).to include("can't be blank")
      end

      it "requires distribution_value to be greater than 0" do
        rule = build(:variant_distribution_rule, distribution_type: :count, distribution_value: 0)
        expect(rule).not_to be_valid

        rule = build(:variant_distribution_rule, distribution_type: :count, distribution_value: 10)
        expect(rule).to be_valid
      end
    end

    context "when distribution_type is unlimited" do
      it "does not require distribution_value" do
        rule = build(:variant_distribution_rule, distribution_type: :unlimited, distribution_value: nil)
        expect(rule).to be_valid
      end
    end
  end

  describe "#slots_available?" do
    context "when distribution_type is unlimited" do
      it "returns true regardless of current assignment count" do
        rule = build(:variant_distribution_rule, distribution_type: :unlimited)
        expect(rule.slots_available?(0)).to be true
        expect(rule.slots_available?(1000)).to be true
      end
    end

    context "when distribution_type is percentage" do
      it "returns true" do
        rule = build(:variant_distribution_rule, distribution_type: :percentage, distribution_value: 50)
        expect(rule.slots_available?(0)).to be true
        expect(rule.slots_available?(100)).to be true
      end
    end

    context "when distribution_type is count" do
      it "returns true when current count is less than distribution_value" do
        rule = build(:variant_distribution_rule, distribution_type: :count, distribution_value: 10)
        expect(rule.slots_available?(5)).to be true
        expect(rule.slots_available?(9)).to be true
      end

      it "returns false when current count equals or exceeds distribution_value" do
        rule = build(:variant_distribution_rule, distribution_type: :count, distribution_value: 10)
        expect(rule.slots_available?(10)).to be false
        expect(rule.slots_available?(15)).to be false
      end
    end
  end
end
