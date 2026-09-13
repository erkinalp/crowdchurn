# frozen_string_literal: true

require "digest"

class FundCart::ReconciliationService
  # These must be server-owned integrations, not operator-supplied JSON attestations.
  class_attribute :backing_verifier, :write_barrier, default: nil

  Report = Struct.new(:snapshot, :fingerprint, :blockers, :evidence, keyword_init: true) do
    def activatable? = blockers.empty?

    def as_json(*)
      { mode: "dry_run", activatable: activatable?, fingerprint:, blockers:, snapshot:, evidence: }
    end
  end

  class Blocked < FundCart::SettlementError
    attr_reader :report

    def initialize(report)
      @report = report
      super("historical_reconciliation_blocked")
    end
  end

  def initialize(fund_cart:, backing_verifier: self.class.backing_verifier, write_barrier: self.class.write_barrier)
    @cart = fund_cart
    @backing_verifier = backing_verifier
    @write_barrier = write_barrier
  end

  # No writes, provider requests, jobs, or balance projection refreshes by default.
  def dry_run(verify_backing: false)
    snapshot = read_snapshot
    fingerprint = digest(snapshot)
    blockers = local_blockers(snapshot)
    blockers << issue("write_barrier_unavailable") unless @write_barrier
    blockers << issue("current_backing_verifier_unavailable") if !@backing_verifier && snapshot.fetch("sources").any? { |source| source["successful"] }
    evidence = {}
    if verify_backing && @backing_verifier
      raise FundCart::SettlementError, "external_request_inside_transaction" if ApplicationRecord.connection.transaction_open?
      evidence = @backing_verifier.inspect_backing(fund_cart: @cart, snapshot:, fingerprint:)
      raise FundCart::SettlementError, "invalid_backing_verifier_response" unless evidence.is_a?(Hash)
      expected_ids = snapshot.fetch("sources").filter_map { |source| source.fetch("id").to_s if source["successful"] }.sort
      blockers << issue("historical_backing_source_set_mismatch") unless evidence.keys.all? { |key| key.is_a?(String) } && evidence.keys.sort == expected_ids
      references = evidence.values.filter_map { |value| value["reserve_reference"] if value.is_a?(Hash) }
      blockers << issue("duplicate_reserve_reference") unless references.uniq.size == references.size
    end
    snapshot.fetch("sources").select { |source| source["successful"] }.each do |source|
      code = evidence_error(source, evidence[source.fetch("id").to_s], fingerprint)
      blockers << issue(code, source_purchase_id: source["id"]) if code
    end
    Report.new(snapshot:, fingerprint:, blockers:, evidence:)
  end

  # A row lock alone cannot fence old callbacks, payout workers or provider webhooks.
  def activate!(expected_fingerprint:)
    raise FundCart::SettlementError, "reconciliation_requires_primary" unless ApplicationRecord.current_role == :writing
    raise FundCart::SettlementError, "external_request_inside_transaction" if ApplicationRecord.connection.transaction_open?
    raise FundCart::SettlementError, "write_barrier_unavailable" unless @write_barrier
    @write_barrier.with_paused_writes(fund_cart: @cart) do |pause|
      pause.assert_held!
      validate_pause!(pause)
      previous = activation_operation
      return replay!(previous, expected_fingerprint) if previous

      report = dry_run(verify_backing: true)
      raise FundCart::SettlementError, "reconciliation_snapshot_changed" unless report.fingerprint == expected_fingerprint
      raise Blocked, report unless report.activatable?

      @cart.with_lock do
        pause.assert_held!
        previous = activation_operation
        return replay!(previous, expected_fingerprint) if previous
        raise FundCart::SettlementError, "reconciliation_snapshot_changed" unless digest(read_snapshot) == report.fingerprint
        raise FundCart::SettlementError, "cart_already_activated" if @cart.ledger_active?
        # Recheck expiry after lock acquisition, not just before waiting for the lock.
        report.snapshot.fetch("sources").select { |source| source["successful"] }.each do |source|
          code = evidence_error(source, report.evidence[source.fetch("id").to_s], report.fingerprint)
          raise FundCart::SettlementError, code if code
          import_source!(source, report.evidence.fetch(source.fetch("id").to_s))
        end
        receipt = {
          "kind" => "historical_reconciliation_v1", "fingerprint" => report.fingerprint,
          "source_high_water_mark" => report.snapshot.fetch("source_high_water_mark"),
          "write_pause" => pause.evidence, "source_ids" => report.evidence.keys.sort,
          "legacy_counter_observed" => report.snapshot.fetch("cart").fetch("balance_subunits")
        }
        operation = @cart.settlement_operations.create!(operation_key: activation_key, kind: "reconciliation_activation",
                                                        state: "completed", payload: receipt, completed_at: Time.current)
        @cart.update!(ledger_state: "active", ledger_activated_at: Time.current, activation_evidence: receipt)
        @cart.refresh_balance_projection!
        pause.assert_held!
        report.snapshot.fetch("sources").select { |source| source["successful"] }.each do |source|
          code = evidence_error(source, report.evidence.fetch(source.fetch("id").to_s), report.fingerprint)
          raise FundCart::SettlementError, code if code
        end
        operation
      end
    end
  end

  private
    def activation_key = "reconcile-activate:#{@cart.id}"
    def activation_operation = @cart.settlement_operations.find_by(operation_key: activation_key)
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value.as_json))
    def issue(code, **details) = { "code" => code }.merge(details.stringify_keys)

    def replay!(operation, fingerprint)
      unless operation.state == "completed" && operation.payload["fingerprint"] == fingerprint && @cart.reload.ledger_active?
        raise FundCart::SettlementError, "activation_replay_mismatch"
      end
      operation
    end

    def validate_pause!(pause)
      evidence = pause.evidence
      unless evidence.is_a?(Hash) && evidence["reference"].present? && evidence["events_through"].present? &&
          %w[legacy_writers_drained new_callbacks_journaled payouts_paused].all? { |key| evidence[key] == true }
        raise FundCart::SettlementError, "write_pause_unverified"
      end
    end

    def read_snapshot
      cart = @cart.reload
      sources = Purchase.where(link_id: cart.link_id).order(:id).map { |purchase| source_snapshot(purchase) }
      items = cart.fund_cart_items.order(:id).map do |item|
        purchase = item.purchase
        settlement = purchase && FundCartSettlement.find_by(purchase_id: purchase.id)
        item.attributes.slice("id", "product_id", "state", "purchase_id", "purchased_at", "updated_at").merge(
          "purchase_state" => purchase&.purchase_state,
          "total_transaction_subunits" => purchase&.total_transaction_cents,
          "valid_receipt" => settlement ? settlement.valid_receipt_for?(purchase) : false,
          "purchase_financials" => purchase && source_snapshot(purchase)
        )
      end
      lots = cart.funding_lots.order(:id).map do |lot|
        lot.attributes.except("external_id").merge("backed" => lot.backed?)
      end
      {
        "cart" => cart.attributes.slice("id", "user_id", "link_id", "currency", "ledger_state", "balance_subunits", "updated_at"),
        "source_high_water_mark" => sources.map { |source| source["id"] }.max || 0,
        "sources" => sources, "items" => items, "lots" => lots,
        "settlements" => cart.settlements.order(:id).map { |record| record.attributes.except("external_id", "quote_snapshot") },
        "allocations" => FundCartSettlementAllocation.where(fund_cart_funding_lot_id: cart.funding_lots.select(:id)).order(:id).map(&:attributes),
        "operations" => cart.settlement_operations.order(:id).map { |record| record.attributes.except("last_error") },
        "ledger" => cart.ledger_entries.order(:id).map(&:attributes)
      }.as_json
    end

    def source_snapshot(purchase)
      account = purchase.charge&.merchant_account || purchase.merchant_account
      result = FundCart::Eligibility.account_result(account)
      refunds = purchase.refunds.order(:id).to_a
      disputes = Dispute.where(purchase_id: purchase.id)
      disputes = disputes.or(Dispute.where(charge_id: purchase.charge.id)) if purchase.charge
      credits = Credit.where(chargebacked_purchase_id: purchase.id).or(Credit.where(dispute_id: disputes.select(:id)))
        .or(Credit.where(refund_id: refunds.map(&:id))).or(Credit.where(fee_retention_refund_id: refunds.map(&:id)))
        .or(Credit.where(failed_refund_id: refunds.map(&:id))).order(:id).to_a
      transactions = BalanceTransaction.where(purchase_id: purchase.id)
        .or(BalanceTransaction.where(refund_id: refunds.map(&:id)))
        .or(BalanceTransaction.where(dispute_id: disputes.select(:id)))
        .or(BalanceTransaction.where(credit_id: credits.map(&:id))).order(:id).to_a
      balance_ids = transactions.map(&:balance_id) + credits.map(&:balance_id) + [purchase.purchase_success_balance_id, purchase.purchase_refund_balance_id, purchase.purchase_chargeback_balance_id]
      balances = Balance.where(id: balance_ids.compact.uniq).order(:id).map do |balance|
        balance.attributes.merge("payments" => balance.payments.order(:id).map do |payment|
          payment.attributes.slice("id", "state", "amount_cents", "currency", "amount_cents_in_local_currency", "processor", "txn_id", "stripe_transfer_id", "stripe_internal_transfer_id", "processor_reversing_payout_id", "updated_at")
        end)
      end
      purchase.attributes.slice("id", "seller_id", "purchase_state", "price_cents", "fee_cents", "tax_cents", "gumroad_tax_cents", "shipping_cents", "purchase_success_balance_id", "created_at", "updated_at").merge(
        "successful" => purchase.successful? && !purchase.is_test_purchase?, "test" => purchase.is_test_purchase?,
        "source_payment_id" => purchase.charge&.processor_transaction_id || purchase.stripe_transaction_id,
        "charge_id" => purchase.charge&.id,
        "charge" => purchase.charge&.attributes&.slice("id", "amount_cents", "gumroad_amount_cents", "processor", "processor_fee_cents", "processor_fee_currency", "processor_transaction_id", "disputed_at", "dispute_reversed_at", "updated_at"),
        "charge_presentment" => purchase.charge && ChargePresentment.find_by(charge_id: purchase.charge.id)&.attributes,
        "merchant_account_id" => account&.id, "processor" => account&.charge_processor_id,
        "custody_key" => result.custody_key, "route_error" => result.code,
        "independent_merchant" => purchase.seller.merchant_accounts.alive.charge_processor_alive.exists?,
        "gross_subunits" => purchase.total_transaction_cents, "net_subunits" => purchase.payment_cents - purchase.affiliate_credit_cents,
        "affiliate_subunits" => purchase.affiliate_credit_cents,
        "canonical_currency" => Currency.base, "canonical_currency_exponent" => 2,
        "listed_currency" => purchase.displayed_price_currency_type.to_s, "listed_subunits" => purchase.displayed_price_cents,
        "buyer_presentment_currency" => purchase.buyer_presentment? ? purchase.buyer_presentment_currency : nil,
        "rate_converted_to_base" => purchase.rate_converted_to_usd.to_s,
        "reversed" => purchase.stripe_refunded? || purchase.stripe_partially_refunded? || purchase.chargedback_not_reversed?,
        "refunds" => refunds.map do |refund|
          refund.attributes.slice("id", "status", "amount_cents", "total_transaction_cents", "processor_refund_id", "updated_at").merge(
            "canonical_currency" => Currency.base, "balance_reversed_on_failure" => refund.balance_reversed_on_failure,
            "presentment_currency" => refund.presentment_currency, "presentment_amount_cents" => refund.presentment_amount_cents,
            "presentment_settled_currency" => refund.presentment_settled_currency, "presentment_settled_amount_cents" => refund.presentment_settled_amount_cents
          )
        end,
        "disputes" => disputes.order(:id).map { |dispute| dispute.attributes.slice("id", "state", "charge_id", "purchase_id", "charge_processor_id", "charge_processor_dispute_id", "event_created_at", "updated_at") },
        "credits" => credits.map { |credit| credit.attributes.slice("id", "balance_id", "amount_cents", "merchant_account_id", "chargebacked_purchase_id", "dispute_id", "refund_id", "fee_retention_refund_id", "failed_refund_id", "updated_at") },
        "balance_transactions" => transactions.map(&:attributes), "balances" => balances
      )
    end

    def local_blockers(snapshot)
      issues = []
      cart = snapshot.fetch("cart")
      issues << issue("cart_already_activated") if cart["ledger_state"] == "active"
      issues << issue("currency_conversion_not_supported") unless FundCart::Eligibility.currency_supported?(cart["currency"])
      snapshot.fetch("sources").each do |source|
        next if source["test"]
        id = source.fetch("id")
        if !source["successful"] && !(source["purchase_state"] == "not_charged" && source["price_cents"].zero? && source["source_payment_id"].blank?)
          issues << issue("source_outcome_requires_reconciliation", source_purchase_id: id)
        end
        issues << issue("source_reversal_requires_reconciliation", source_purchase_id: id) if source["reversed"] || source["refunds"].any? || source["disputes"].any? || source["credits"].any?
        next unless source["successful"]
        issues << issue(source["route_error"], source_purchase_id: id) if source["route_error"]
        issues << issue("external_merchant_reservation_unverified", source_purchase_id: id) if source["independent_merchant"]
        issues << issue("source_payment_missing", source_purchase_id: id) if source["source_payment_id"].blank?
        issues << issue("source_net_not_positive", source_purchase_id: id) unless source["net_subunits"].positive?
        if source["seller_id"] != cart["user_id"] || source["listed_currency"] != cart["currency"] || (source["buyer_presentment_currency"] && source["buyer_presentment_currency"] != cart["currency"])
          issues << issue("source_dimensions_mismatch", source_purchase_id: id)
        end
        seller_transactions = source["balance_transactions"].select { |transaction| transaction["user_id"] == source["seller_id"] }
        if source["purchase_success_balance_id"] || seller_transactions.any?
          issues << issue("historical_seller_credit_requires_restriction_api", source_purchase_id: id)
        end
        if seller_transactions.count { |transaction| transaction["purchase_id"] == id && transaction["holding_amount_net_cents"].to_i.positive? } > 1
          issues << issue("duplicate_source_credit", source_purchase_id: id)
        end
        source["balances"].each do |balance|
          if balance["state"] != "unpaid" || balance["payments"].any?
            issues << issue("payout_history_requires_recovery", source_purchase_id: id, balance_id: balance["id"])
          end
        end
      end
      snapshot.fetch("sources").select { |source| source["successful"] && source["source_payment_id"].present? }
        .group_by { |source| [source["custody_key"], source["source_payment_id"]] }.each_value do |group|
        next if group.size == 1 || (group.all? { |source| source["charge_id"].present? } && group.map { |source| source["charge_id"] }.uniq.size == 1)
        issues << issue("duplicate_source_payment", source_purchase_ids: group.map { |source| source["id"] })
      end
      snapshot.fetch("items").each do |item|
        if (item["purchase_id"] || item["state"] == "purchased") && !item["valid_receipt"]
          issues << issue("ambiguous_paid_item", item_id: item["id"], purchase_id: item["purchase_id"])
        end
      end
      if snapshot.fetch("lots").any? || snapshot.fetch("settlements").any? || snapshot.fetch("operations").any? || snapshot.fetch("ledger").any?
        issues << issue("existing_ledger_requires_review")
      elsif snapshot.fetch("items").none? { |item| item["state"] == "purchased" || item["purchase_id"] }
        nominal_counter = snapshot.fetch("sources").select { |source| source["successful"] }.sum { |source| source["price_cents"] }
        issues << issue("legacy_counter_mismatch", expected_nominal_subunits: nominal_counter, observed_subunits: cart["balance_subunits"]) unless nominal_counter == cart["balance_subunits"]
      end
      audit_ledger(snapshot, issues)
      issues
    end

    def audit_ledger(snapshot, issues)
      snapshot.fetch("ledger").group_by { |entry| entry.values_at("fund_cart_settlement_operation_id", "currency", "currency_exponent") }.each do |key, entries|
        issues << issue("unbalanced_ledger", operation_id: key.first) unless entries.sum { |entry| BigDecimal(entry["amount_subunits"].to_s) }.zero?
      end
      snapshot.fetch("lots").each do |lot|
        id = lot.fetch("id")
        amounts = %w[available reserved spent reversed debt].index_with { |name| BigDecimal(lot.fetch("#{name}_subunits").to_s) }
        unless amounts.values.all? { |amount| amount >= 0 } && (!lot["confirmed_at"] || amounts.values_at("available", "reserved", "spent", "reversed").sum == BigDecimal(lot.fetch("net_subunits").to_s) + amounts["debt"])
          issues << issue("lot_backing_mismatch", lot_id: id)
        end
        issues << issue("lot_custody_unverified", lot_id: id) unless lot["backed"]
        issues << issue("owner_debt_requires_recovery", lot_id: id) if amounts["debt"].positive?
        %w[available reserved].each do |account|
          entries = snapshot.fetch("ledger").select { |entry| entry["fund_cart_funding_lot_id"] == id && entry["account"] == account && entry["currency"] == lot["currency"] }
          issues << issue("lot_ledger_mismatch", lot_id: id, account:) unless entries.sum { |entry| BigDecimal(entry["amount_subunits"].to_s) } == amounts[account]
        end
        reservations = snapshot.fetch("allocations").select { |allocation| allocation["fund_cart_funding_lot_id"] == id && allocation["state"].in?(%w[reserved reconciling]) }
        issues << issue("lot_allocation_mismatch", lot_id: id) unless reservations.sum { |allocation| BigDecimal(allocation["amount_subunits"].to_s) } == amounts["reserved"]
      end
    end

    def evidence_error(source, evidence, fingerprint)
      return "current_backing_unverified" unless evidence.is_a?(Hash)
      expected = {
        "fund_cart_id" => @cart.id, "source_purchase_id" => source["id"], "beneficiary_id" => @cart.user_id,
        "source_merchant_account_id" => source["merchant_account_id"], "custody_key" => source["custody_key"],
        "payment_id" => source["source_payment_id"], "snapshot_fingerprint" => fingerprint,
        "currency" => @cart.currency, "currency_exponent" => 2,
        "source_gross_subunits" => source["gross_subunits"], "source_net_subunits" => source["net_subunits"],
        "reserved_subunits" => source["net_subunits"], "prior_payout_status" => "never_paid", "current_backing_status" => "held"
      }
      return "historical_backing_evidence_mismatch" unless expected.all? { |key, value| evidence[key] == value }
      return "historical_backing_evidence_incomplete" unless %w[balance_transaction_id reserve_reference payout_lookup_reference current_balance_reference].all? { |key| evidence[key].is_a?(String) && evidence[key].present? }
      return "historical_backing_amount_not_integer" unless %w[source_gross_subunits source_net_subunits reserved_subunits].all? { |key| evidence[key].is_a?(Integer) }
      return "historical_backing_evidence_expired" unless evidence["verified_at"].is_a?(Integer) && evidence["expires_at"].is_a?(Integer) && evidence["available_at"].is_a?(Integer) &&
        evidence["verified_at"] <= Time.current.to_i && evidence["verified_at"] >= 5.minutes.ago.to_i && evidence["expires_at"] > Time.current.to_i && evidence["available_at"] <= Time.current.to_i
      nil
    end

    def import_source!(source, evidence)
      if FundCartFundingLot.exists?(source_purchase_id: source.fetch("id")) || FundCartFundingLot.exists?(reserve_reference: evidence.fetch("reserve_reference"))
        raise FundCart::SettlementError, "duplicate_source_credit"
      end
      confirmation = evidence.merge("available_at" => Time.zone.at(evidence.fetch("available_at")).iso8601)
      lot = @cart.funding_lots.create!(
        source_purchase_id: source.fetch("id"), beneficiary_id: @cart.user_id,
        source_merchant_account_id: source.fetch("merchant_account_id"), processor: source.fetch("processor"),
        custody_key: source.fetch("custody_key"), currency: @cart.currency, currency_exponent: evidence.fetch("currency_exponent"),
        canonical_currency: source.fetch("canonical_currency"), canonical_currency_exponent: source.fetch("canonical_currency_exponent"),
        gross_subunits: source.fetch("gross_subunits"), fee_subunits: source.fetch("fee_cents"), tax_subunits: source.fetch("gumroad_tax_cents"),
        affiliate_subunits: source.fetch("affiliate_subunits"), net_subunits: source.fetch("net_subunits"),
        native_currency: evidence.fetch("currency"), native_currency_exponent: evidence.fetch("currency_exponent"),
        native_gross_subunits: evidence.fetch("source_gross_subunits"), native_net_subunits: evidence.fetch("source_net_subunits"),
        source_payment_id: evidence.fetch("payment_id"), source_balance_transaction_id: evidence.fetch("balance_transaction_id"),
        reserve_reference: evidence.fetch("reserve_reference"), restricted_at: Time.zone.at(evidence.fetch("verified_at")),
        confirmed_at: Time.current, available_at: Time.zone.at(evidence.fetch("available_at")), confirmation_evidence: confirmation,
        amount_snapshot: source.slice("canonical_currency", "canonical_currency_exponent", "gross_subunits", "net_subunits", "affiliate_subunits", "listed_currency", "listed_subunits", "rate_converted_to_base").merge(
          "price_subunits" => source.fetch("price_cents"), "fee_subunits" => source.fetch("fee_cents"),
          "seller_tax_subunits" => source.fetch("tax_cents"), "platform_tax_subunits" => source.fetch("gumroad_tax_cents"),
          "shipping_subunits" => source.fetch("shipping_cents")
        ),
        state: "available", available_subunits: source.fetch("net_subunits")
      )
      operation = @cart.settlement_operations.create!(operation_key: "source-credit:#{source.fetch('id')}", kind: "ledger", state: "processing", fund_cart_funding_lot: lot)
      dimensions = { currency: lot.currency, currency_exponent: lot.currency_exponent, fund_cart_funding_lot_id: lot.id,
                     user_id: lot.beneficiary_id, merchant_account_id: lot.source_merchant_account_id }
      FundCart::Ledger.post!(operation:, postings: [dimensions.merge(account: "source_custody", amount_subunits: -lot.net_subunits), dimensions.merge(account: "available", amount_subunits: lot.net_subunits)])
      operation.update!(state: "completed", completed_at: Time.current, external_references: evidence)
    end
end
