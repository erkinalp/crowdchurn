# frozen_string_literal: true

describe FundCart::ReconciliationService do
  let(:cart) { create(:fund_cart_product).fund_cart.tap { |cart| cart.update!(ledger_state: "legacy", ledger_activated_at: nil, activation_evidence: nil) } }
  let(:operator) { create(:merchant_account, user: nil) }
  let(:source) { create(:purchase, :with_custom_fee, link: cart.link, merchant_account: operator, price_cents: 5000, fee_cents: 500) }
  let(:service) { described_class.new(fund_cart: cart) }

  def codes(report)
    report.blockers.map { |blocker| blocker.fetch("code") }
  end

  describe "read-only historical audit" do
    it "never imports aggregate counters, contacts Stripe or queues work" do
      cart.update!(balance_subunits: 5000)
      original = cart.attributes
      expect(FundCart::StripeCustody).not_to receive(:confirm)
      expect(Stripe::Charge).not_to receive(:retrieve)
      jobs = FundCartOperationJob.jobs.size
      report = service.dry_run
      expect(codes(report)).to include("legacy_counter_mismatch", "write_barrier_unavailable")
      expect(report).not_to be_activatable
      expect(cart.reload.attributes).to eq(original)
      expect(cart.funding_lots.count).to eq(0)
      expect(cart.ledger_entries.count).to eq(0)
      expect(cart.settlement_operations.count).to eq(0)
      expect(FundCartOperationJob.jobs.size).to eq(jobs)
    end

    it "lists successful source amounts separately from unverified current backing" do
      cart.update!(balance_subunits: source.price_cents)
      report = service.dry_run
      expect(codes(report)).to include("current_backing_unverified", "current_backing_verifier_unavailable")
      expect(codes(report)).not_to include("legacy_counter_mismatch")
      expect(report.snapshot.fetch("sources").first).to include("id" => source.id, "gross_subunits" => 5000, "net_subunits" => 4500, "canonical_currency" => Currency.base)
      expect(report.snapshot.fetch("source_high_water_mark")).to eq(source.id)
      expect(service.dry_run.fingerprint).to eq(report.fingerprint)
    end

    it "does not turn a replayed legacy callback into new backing" do
      cart.update!(balance_subunits: source.price_cents)
      2.times { FundCart::ContributeService.new(purchase: source).perform }
      expect(cart.funding_lots.count).to eq(0)
      expect(codes(service.dry_run)).to include("current_backing_unverified")
      expect(cart.reload.balance_subunits).to eq(source.price_cents)
    end

    it "blocks an unexplained duplicate nominal counter" do
      cart.update!(balance_subunits: source.price_cents * 2)
      expect(codes(service.dry_run)).to include("legacy_counter_mismatch")
    end

    it "blocks two purchases reusing an unallocated source payment reference" do
      other = create(:purchase, :with_custom_fee, link: cart.link, merchant_account: operator, price_cents: 1000, fee_cents: 100, stripe_transaction_id: source.stripe_transaction_id)
      cart.update!(balance_subunits: source.price_cents + other.price_cents)
      expect(codes(service.dry_run)).to include("duplicate_source_payment")
    end

    it "does not mistake a successful item purchase for a backed settlement" do
      destination = create(:purchase, purchaser: cart.user, merchant_account: operator)
      item = create(:fund_cart_item, fund_cart: cart, product: destination.link, purchase: destination, state: "purchased")
      report = service.dry_run
      expect(report.blockers).to include("code" => "ambiguous_paid_item", "item_id" => item.id, "purchase_id" => destination.id)
      expect(item.reload.purchase_id).to eq(destination.id)
      expect(cart.settlements.count).to eq(0)
    end

    it "blocks purchase reversal flags even when there is no modern dispute record" do
      source.update!(chargeback_date: Time.current)
      cart.update!(balance_subunits: source.price_cents)
      expect(codes(service.dry_run)).to include("source_reversal_requires_reconciliation")
    end

    it "includes all refund evidence without restoring failed refunds by assumption" do
      refund = create(:refund, purchase: source, status: "failed")
      cart.update!(balance_subunits: source.price_cents)
      report = service.dry_run
      expect(codes(report)).to include("source_reversal_requires_reconciliation")
      expect(report.snapshot.fetch("sources").first.fetch("refunds").map { |row| row.fetch("id") }).to eq([refund.id])
    end

    it "blocks payout history even if a balance has returned to unpaid" do
      balance = create(:balance, user: cart.user, merchant_account: operator)
      payment = create(:payment, user: cart.user)
      balance.payments << payment
      source.update!(purchase_success_balance: balance)
      cart.update!(balance_subunits: source.price_cents)
      report = service.dry_run
      expect(codes(report)).to include("payout_history_requires_recovery", "historical_seller_credit_requires_restriction_api")
      expect(report.snapshot.fetch("sources").first.fetch("balances").first.fetch("payments").first.fetch("id")).to eq(payment.id)
    end

    it "blocks pre-cutover purchases that could complete below the high-water mark" do
      source.update_columns(purchase_state: "in_progress")
      expect(codes(service.dry_run)).to include("source_outcome_requires_reconciliation")
    end

    it "does not treat a locally failed purchase as proof a provider payment never succeeded" do
      source.update!(purchase_state: "failed")
      expect(codes(service.dry_run)).to include("source_outcome_requires_reconciliation")
    end

    it "delegates currency capability checks without assuming conversion" do
      allow(FundCart::Eligibility).to receive(:currency_supported?).with(cart.currency).and_return(false)
      expect(codes(service.dry_run)).to include("currency_conversion_not_supported")
    end
  end

  describe "verified import protocol" do
    self.use_transactional_tests = false

    let(:verifier) { double("CurrentBackingVerifier") }
    let(:pause) { double("DurableWritePause", assert_held!: nil, evidence: { "reference" => "fixture-pause", "events_through" => "fixture-event-cursor", "legacy_writers_drained" => true, "new_callbacks_journaled" => true, "payouts_paused" => true }) }
    let(:barrier) { double("WriteBarrier") }
    let(:service) { described_class.new(fund_cart: cart, backing_verifier: verifier, write_barrier: barrier) }
    let(:evidence_changes) { {} }

    before do
      cart.update!(balance_subunits: source.price_cents)
      allow(barrier).to receive(:with_paused_writes).with(fund_cart: cart).and_yield(pause)
      # Protocol fixtures are not an implementation of custody/payout verification.
      allow(verifier).to receive(:inspect_backing) do |fund_cart:, snapshot:, fingerprint:|
        snapshot.fetch("sources").to_h do |row|
          [row.fetch("id").to_s, {
            "fund_cart_id" => fund_cart.id, "source_purchase_id" => row.fetch("id"), "beneficiary_id" => cart.user_id,
            "source_merchant_account_id" => row.fetch("merchant_account_id"), "custody_key" => row.fetch("custody_key"),
            "payment_id" => row.fetch("source_payment_id"), "snapshot_fingerprint" => fingerprint,
            "currency" => cart.currency, "currency_exponent" => 2, "source_gross_subunits" => row.fetch("gross_subunits"),
            "source_net_subunits" => row.fetch("net_subunits"), "reserved_subunits" => row.fetch("net_subunits"),
            "prior_payout_status" => "never_paid", "current_backing_status" => "held",
            "balance_transaction_id" => "fixture-balance-#{row.fetch('id')}", "reserve_reference" => "fixture-reserve-#{row.fetch('id')}",
            "payout_lookup_reference" => "fixture-payout-lookup", "current_balance_reference" => "fixture-current-balance",
            "verified_at" => Time.current.to_i, "available_at" => 1.hour.ago.to_i, "expires_at" => 2.minutes.from_now.to_i
          }.merge(evidence_changes)]
        end
      end
    end

    after do
      purchase_ids = Purchase.where(link_id: cart.link_id).pluck(:id)
      FundCartLedgerEntry.where(fund_cart_id: cart.id).delete_all
      FundCartSettlementOperation.where(fund_cart_id: cart.id).delete_all
      FundCartFundingLot.where(fund_cart_id: cart.id).delete_all
      PurchasePaymentFlow.where(purchase_id: purchase_ids).delete_all
      PurchaseSalesTaxInfo.where(purchase_id: purchase_ids).delete_all
      Purchase.where(id: purchase_ids).delete_all
      cart.delete
      Price.where(link_id: cart.link_id).delete_all
      cart.link.delete
      operator.delete
      cart.user.delete
    end

    it "imports proven net source backing atomically, never the nominal counter" do
      report = service.dry_run(verify_backing: true)
      expect(report).to be_activatable
      jobs = FundCartOperationJob.jobs.size
      operation = service.activate!(expected_fingerprint: report.fingerprint)
      lot = cart.funding_lots.sole
      expect(lot.net_subunits).to eq(4500)
      expect(lot.native_net_subunits).to eq(4500)
      expect(lot.native_currency).to eq("usd")
      expect(lot).to be_backed
      expect(cart.reload.balance_subunits).to eq(4500)
      expect(cart.available_subunits).to eq(4500)
      expect(lot.ledger_entries.sum(:amount_subunits)).to eq(0)
      expect(operation.payload).to include("fingerprint" => report.fingerprint, "source_high_water_mark" => source.id)
      expect(operation.payload.fetch("write_pause")).to eq(pause.evidence)
      expect(FundCartOperationJob.jobs.size).to eq(jobs)
      expect(pause).to have_received(:assert_held!).at_least(:twice)
    end

    it "replays activation and successful source callbacks without duplicate credits" do
      fingerprint = service.dry_run.fingerprint
      first = service.activate!(expected_fingerprint: fingerprint)
      second = service.activate!(expected_fingerprint: fingerprint)
      FundCart::ContributeService.new(purchase: source).perform
      FundCart::ContributeService.confirm!(lot: cart.funding_lots.sole)
      expect(second.id).to eq(first.id)
      expect(cart.funding_lots.count).to eq(1)
      expect(cart.ledger_entries.count).to eq(2)
      expect(cart.available_subunits).to eq(4500)
      expect { service.activate!(expected_fingerprint: "different") }.to raise_error(FundCart::SettlementError, "activation_replay_mismatch")
    end

    it "rolls back lots and postings if the activation transaction fails" do
      fingerprint = service.dry_run.fingerprint
      allow(cart).to receive(:refresh_balance_projection!).and_raise(FundCart::SettlementError, "fixture_commit_failure")
      expect { service.activate!(expected_fingerprint: fingerprint) }.to raise_error(FundCart::SettlementError, "fixture_commit_failure")
      expect(cart.reload.ledger_state).to eq("legacy")
      expect(cart.balance_subunits).to eq(5000)
      expect(cart.funding_lots.count).to eq(0)
      expect(cart.ledger_entries.count).to eq(0)
      expect(cart.settlement_operations.count).to eq(0)
    end

    it "rejects a counter change made after review" do
      fingerprint = service.dry_run.fingerprint
      cart.update!(balance_subunits: 6000)
      expect { service.activate!(expected_fingerprint: fingerprint) }.to raise_error(FundCart::SettlementError, "reconciliation_snapshot_changed")
      expect(cart.funding_lots.count).to eq(0)
    end

    it "rejects a source arriving after the reviewed high-water mark" do
      fingerprint = service.dry_run.fingerprint
      create(:purchase, :with_custom_fee, link: cart.link, merchant_account: operator, price_cents: 1000, fee_cents: 100)
      expect { service.activate!(expected_fingerprint: fingerprint) }.to raise_error(FundCart::SettlementError, "reconciliation_snapshot_changed")
      expect(cart.funding_lots.count).to eq(0)
    end

    it "rechecks the database snapshot after acquiring the cart lock" do
      fingerprint = service.dry_run.fingerprint
      allow(cart).to receive(:with_lock).and_wrap_original do |method, &block|
        cart.update!(balance_subunits: 6000)
        method.call(&block)
      end
      expect { service.activate!(expected_fingerprint: fingerprint) }.to raise_error(FundCart::SettlementError, "reconciliation_snapshot_changed")
      expect(cart.funding_lots.count).to eq(0)
    end

    it "fails closed without a write barrier" do
      unconfigured = described_class.new(fund_cart: cart, backing_verifier: verifier, write_barrier: nil)
      expect { unconfigured.activate!(expected_fingerprint: unconfigured.dry_run.fingerprint) }.to raise_error(FundCart::SettlementError, "write_barrier_unavailable")
      expect(cart.funding_lots.count).to eq(0)
    end

    it "fails closed when the pause fence is lost before the database lock" do
      allow(pause).to receive(:assert_held!).and_raise(FundCart::SettlementError, "pause_lost")
      expect { service.activate!(expected_fingerprint: service.dry_run.fingerprint) }.to raise_error(FundCart::SettlementError, "pause_lost")
      expect(cart.funding_lots.count).to eq(0)
    end

    it "rolls back the import if the write pause is lost before commit" do
      checks = 0
      allow(pause).to receive(:assert_held!) do
        checks += 1
        raise FundCart::SettlementError, "pause_lost" if checks == 3
      end
      expect { service.activate!(expected_fingerprint: service.dry_run.fingerprint) }.to raise_error(FundCart::SettlementError, "pause_lost")
      expect(cart.reload.ledger_state).to eq("legacy")
      expect(cart.funding_lots.count).to eq(0)
      expect(cart.ledger_entries.count).to eq(0)
      expect(cart.settlement_operations.count).to eq(0)
    end

    context "with a floating-point native amount" do
      let(:evidence_changes) { { "source_net_subunits" => 4500.0 } }

      it "rejects float evidence even when numerically equal to integer base units" do
        expect(codes(service.dry_run(verify_backing: true))).to include("historical_backing_amount_not_integer")
        expect { service.activate!(expected_fingerprint: service.dry_run.fingerprint) }.to raise_error(described_class::Blocked)
      end
    end

    context "with funds already paid out" do
      let(:evidence_changes) { { "prior_payout_status" => "paid" } }

      it "refuses import rather than relabeling a prior capture as current money" do
        expect(codes(service.dry_run(verify_backing: true))).to include("historical_backing_evidence_mismatch")
        expect { service.activate!(expected_fingerprint: service.dry_run.fingerprint) }.to raise_error(described_class::Blocked)
        expect(cart.funding_lots.count).to eq(0)
      end
    end

    context "with a mismatched native currency" do
      let(:evidence_changes) { { "currency" => "eur" } }

      it "does not relabel native proceeds as canonical USD" do
        expect(codes(service.dry_run(verify_backing: true))).to include("historical_backing_evidence_mismatch")
        expect { service.activate!(expected_fingerprint: service.dry_run.fingerprint) }.to raise_error(described_class::Blocked)
      end
    end

    context "with expired current backing evidence" do
      let(:evidence_changes) { { "expires_at" => 1.second.ago.to_i } }

      it "requires a fresh provider lookup before import" do
        expect(codes(service.dry_run(verify_backing: true))).to include("historical_backing_evidence_expired")
        expect { service.activate!(expected_fingerprint: service.dry_run.fingerprint) }.to raise_error(described_class::Blocked)
      end
    end
  end
end
