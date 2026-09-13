# frozen_string_literal: true

describe FundCartReconciliationJob do
  it "only audits a cart and never schedules activation or payment work" do
    cart = create(:fund_cart_product).fund_cart
    cart.update!(balance_subunits: 1000)
    jobs = FundCartOperationJob.jobs.size
    original = cart.attributes
    expect(FundCart::StripeCustody).not_to receive(:confirm)
    expect(FundCart::AllocateFundsService).not_to receive(:new)
    2.times do
      result = described_class.new.perform(cart.id)
      expect(result.fetch(:mode)).to eq("dry_run")
      expect(result.fetch(:activatable)).to eq(false)
      expect(result.fetch(:blockers).map { |issue| issue.fetch("code") }).to include("legacy_counter_mismatch")
    end
    expect(cart.reload.attributes).to eq(original)
    expect(cart.funding_lots.count).to eq(0)
    expect(cart.settlement_operations.count).to eq(0)
    expect(FundCartOperationJob.jobs.size).to eq(jobs)
  end
end
