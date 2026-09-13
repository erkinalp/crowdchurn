# frozen_string_literal: true

describe FundCartOutboxJob do
  let(:cart) { create(:fund_cart_product).fund_cart }

  it "redispatches due pending work, but never retries an unknown worker outcome" do
    due = cart.settlement_operations.create!(operation_key: "due", kind: "allocate")
    future = cart.settlement_operations.create!(operation_key: "future", kind: "allocate", available_at: 1.day.from_now)
    stale = cart.settlement_operations.create!(operation_key: "stale", kind: "fulfill", state: "processing", started_at: 1.hour.ago)
    FundCartOperationJob.clear
    described_class.new.perform
    expect(FundCartOperationJob.jobs.map { |job| job["args"] }).to eq([[due.id]])
    expect(future.reload.state).to eq("pending")
    expect(stale.reload.state).to eq("reconciling")
    expect(stale.error_code).to eq("worker_outcome_unknown")
  end

  it "claims a completed operation only once" do
    operation = cart.settlement_operations.create!(operation_key: "once", kind: "allocate")
    service = instance_double(FundCart::AllocateFundsService, perform: nil)
    allow(FundCart::AllocateFundsService).to receive(:new).with(fund_cart: cart).and_return(service)
    2.times { FundCartOperationJob.new.perform(operation.id) }
    expect(service).to have_received(:perform).once
    expect(operation.reload.state).to eq("completed")
    expect(operation.attempts).to eq(1)
  end
end
