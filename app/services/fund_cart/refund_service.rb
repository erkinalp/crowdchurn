# frozen_string_literal: true

class FundCart::RefundService
  REFUND_KINDS = %w[source_refund destination_refund].freeze

  def self.handles?(purchase)
    purchase.persisted? && (FundCartFundingLot.exists?(source_purchase_id: purchase.id) || FundCartSettlement.exists?(purchase_id: purchase.id))
  end

  def initialize(purchase:)
    @purchase = purchase
    @lot = FundCartFundingLot.find_by(source_purchase_id: purchase.id)
    @settlement = FundCartSettlement.find_by(purchase_id: purchase.id)
    @cart = (@lot || @settlement)&.fund_cart
  end

  # amount_cents is canonical price (excluding platform tax), as in Purchase#refund_and_save!.
  # Callers retrying a partial request must retain operation_key; callbacks use the provider refund ID.
  def request!(refunding_user_id:, amount_cents: nil, reason: nil, is_for_fraud: false, operation_key: nil, tax_only: false, business_vat_id: nil)
    @purchase.fund_cart_refund_pending = false
    authorize!(refunding_user_id, reason, is_for_fraud)
    raise FundCart::SettlementError, "partial_refund_operation_key_required" if amount_cents && operation_key.blank?
    operation = @cart.with_lock do
      @purchase.reload.lock!
      existing = operations.lock.find_by(operation_key:) if operation_key
      if existing
        validate_request!(existing, amount_cents:, tax_only:)
        next existing
      end
      pending = operations.where(kind: REFUND_KINDS, state: %w[pending processing reconciling]).lock.first
      if pending
        validate_request!(pending, amount_cents:, tax_only:)
        next pending
      end
      raise FundCart::SettlementError, "nothing_to_refund" unless remaining_gross_subunits.positive?
      raise FundCart::SettlementError, "active_contribution_dispute" if @purchase.chargedback_not_reversed?
      amount = amount_cents || remaining_price_subunits
      raise FundCart::SettlementError, "invalid_refund_amount" unless tax_only || (amount.is_a?(Integer) && amount.positive? && amount <= remaining_price_subunits)
      gross = if tax_only
        @purchase.gumroad_tax_refundable_cents
      elsif amount == remaining_price_subunits
        remaining_gross_subunits
      else
        amount + [Rational(amount * @purchase.gumroad_tax_cents, @purchase.price_cents).floor, @purchase.gumroad_tax_refundable_cents].min
      end
      raise FundCart::SettlementError, "nothing_to_refund" unless gross.positive?
      operation = operations.create!(fund_cart: @cart, fund_cart_funding_lot: @lot, fund_cart_settlement: @settlement,
                                     purchase: @purchase, kind: @lot ? "source_refund" : "destination_refund",
                                     operation_key: operation_key || "cart-refund:#{@purchase.id}:#{SecureRandom.uuid}",
                                     payload: { "gross_subunits" => gross, "currency" => currency, "currency_exponent" => exponent,
                                                "refunding_user_id" => refunding_user_id, "reason" => reason, "is_for_fraud" => is_for_fraud,
                                                "tax_only" => tax_only, "requested_amount_subunits" => amount_cents, "business_vat_id" => business_vat_id })
      freeze_source!(operation) if @lot
      operation
    end
    return true if operation.state == "completed" && !operation.refund&.terminally_failed?
    # A combined-charge caller already owns purchase locks. Never send a provider request
    # until that outer transaction (and the durable identity above) has committed.
    if ApplicationRecord.connection.transaction_open?
      @purchase.fund_cart_refund_pending = operation.state.in?(%w[pending processing reconciling])
      @purchase.errors.add(:base, "Fund cart refund queued; confirmation is pending.")
      return false
    end
    FundCartRefundJob.new.perform(operation.id)
    operation.reload
    return true if operation.state == "completed" && !operation.refund&.terminally_failed?
    @purchase.fund_cart_refund_pending = operation.state.in?(%w[pending processing reconciling])
    @purchase.errors.add(:base, "Fund cart refund pending or blocked: #{operation.error_code || operation.refund&.status || operation.state}.")
    false
  rescue FundCart::SettlementError => error
    @purchase.errors.add(:base, "Fund cart refund unavailable: #{error.code}.")
    false
  end

  def perform(operation)
    validate_operation!(operation)
    if @purchase.affiliate_credit_cents.positive?
      raise FundCart::SettlementError, "affiliate_refund_recovery_requires_reconciliation"
    end
    if @lot
      FundCart::ContributeService.confirm!(lot: @lot, for_reversal: true) unless @lot.confirmed_at?
      ensure_source_route!
      # Stripe's ordinary refund helper has no idempotency argument and can lose the
      # refund ID during get_refund. Pin the ID before asking for settlement evidence.
      response = Stripe::Refund.create({ charge: @lot.source_payment_id,
                                         amount: operation.payload.fetch("gross_subunits"),
                                         metadata: { fund_cart_operation: operation.operation_key }, expand: ["balance_transaction"] },
                                       { idempotency_key: operation.operation_key })
      operation.update!(external_references: { "processor_refund_id" => response.id, "source_merchant_account_id" => @lot.source_merchant_account_id })
      observe!(operation, response)
    else
      complete!(operation, flow_of_funds: FlowOfFunds.build_simple_flow_of_funds(currency, -operation.payload.fetch("gross_subunits")))
    end
  end

  # A lookup, never a second refund submission. Pending and ambiguous outcomes retain the freeze.
  def reconcile!(operation)
    validate_operation!(operation, allow_missing_evidence: true)
    return perform(operation) if @settlement
    FundCart::ContributeService.confirm!(lot: @lot, for_reversal: true) unless @lot.confirmed_at?
    ensure_source_route!
    refund_id = operation.external_references&.fetch("processor_refund_id", nil)
    if refund_id.blank?
      matches = Stripe::Refund.list(charge: @lot.source_payment_id, limit: 100).auto_paging_each.select do |refund|
        refund.metadata&.[]("fund_cart_operation") == operation.operation_key
      end
      raise FundCart::SettlementError, "refund_identity_ambiguous" if matches.many?
      refund_id = matches.first&.id
      operation.update!(external_references: { "processor_refund_id" => refund_id }) if refund_id
    end
    raise FundCart::SettlementError, "refund_identity_requires_reconciliation" if refund_id.blank?
    if operation.payload.blank?
      event = ChargeEvent.new
      event.charge_id = @lot.source_payment_id
      event.refund_id = refund_id
      return receive_event!(event)
    end
    response = Stripe::Refund.retrieve(id: refund_id, expand: ["balance_transaction"])
    observe!(operation, response)
  end

  def self.handle_event!(event)
    lots = FundCartFundingLot.joins(:source_purchase)
                             .where("fund_cart_funding_lots.source_payment_id = :id OR purchases.stripe_transaction_id = :id", id: event.charge_id).to_a
    return false if lots.empty?
    matched = FundCartSettlementOperation.where(fund_cart_funding_lot_id: lots.map(&:id), kind: "source_refund")
                                        .detect { |work| work.external_references&.dig("processor_refund_id") == event.refund_id }
    if matched
      new(purchase: matched.purchase).receive_event!(event)
      return true
    end
    if lots.many? || lots.first.source_purchase.charge&.purchases&.many?
      lots.each { |lot| new(purchase: lot.source_purchase).send(:unresolved_external_refund!) }
      return false
    end
    new(purchase: lots.first.source_purchase).receive_event!(event)
    true
  end

  def receive_event!(event, defer_lookup: false)
    return unresolved_external_refund! if event.refund_id.blank?
    operation = @cart.with_lock do
      known = operations.where(kind: "source_refund").lock.detect { |work| work.external_references&.dig("processor_refund_id") == event.refund_id }
      unless known&.state.in?(%w[completed failed cancelled])
        freeze_source!(nil)
      end
      known || operations.create!(fund_cart: @cart, fund_cart_funding_lot: @lot, purchase: @purchase, kind: "source_refund", state: "reconciling",
                                  operation_key: "source-refund:#{@lot.id}:#{event.refund_id}", payload: {},
                                  external_references: { "processor_refund_id" => event.refund_id })
    end
    return false if defer_lookup
    FundCart::ContributeService.confirm!(lot: @lot, for_reversal: true) unless @lot.confirmed_at?
    ensure_source_route!
    response = Stripe::Refund.retrieve(id: event.refund_id, expand: ["balance_transaction"])
    raise FundCart::SettlementError, "source_refund_charge_mismatch" unless response.charge == @lot.source_payment_id
    operation = @cart.with_lock do
      # The webhook may arrive before the API response persists its refund ID.
      key = response.metadata&.[]("fund_cart_operation")
      requested = operations.lock.find_by(operation_key: key) if key.present?
      if requested && requested.id != operation.id
        operation.update!(state: "cancelled", error_code: "joined_original_request")
        operation = requested
      elsif @purchase.charge&.purchases&.many? && operation.payload["gross_subunits"].nil?
        operation.update!(error_code: "combined_source_refund_requires_attribution")
        return false
      end
      payload = operation.payload.presence || { "gross_subunits" => response.amount, "currency" => response.currency, "currency_exponent" => exponent }
      operation.update!(payload:, external_references: (operation.external_references || {}).merge("processor_refund_id" => response.id))
      operation
    end
    observe!(operation, response)
  rescue FundCart::SettlementError => error
    operation&.update!(state: "reconciling", error_code: error.code) unless operation&.reload&.state.in?(%w[completed failed cancelled])
    raise
  end

  def complete!(operation, flow_of_funds:, processor_refund: nil)
    with_accounting_locks do
      operation.reload.lock!
      return true if operation.state == "completed"
      return false if operation.state.in?(%w[failed cancelled])
      validate_operation!(operation)
      @purchase.reload
      completed = if operation.payload["tax_only"]
        complete_tax_refund!(operation, processor_refund, flow_of_funds)
      else
        @purchase.refund_purchase!(flow_of_funds, operation.payload["refunding_user_id"], processor_refund,
                                   operation.payload["is_for_fraud"], note: operation.payload["reason"], fund_cart_operation: operation)
      end
      thaw_source! if completed && @lot
      completed
    end
  end

  # Destination receipts have no ordinary charge processor; its refundable-amount gate cannot apply.
  def build_refund(gross_refund_amount:, refunding_user_id:)
    remaining = @purchase.send(:refundable_amounts)
    unless gross_refund_amount.is_a?(Integer) && gross_refund_amount.positive? && gross_refund_amount <= remaining.fetch(:total_transaction_cents)
      raise FundCart::SettlementError, "invalid_refund_amount"
    end
    return Refund.new(**remaining, refunding_user_id:) if gross_refund_amount == remaining.fetch(:total_transaction_cents)

    platform_tax = [Rational(gross_refund_amount * @purchase.gumroad_tax_cents, @purchase.total_transaction_cents).floor, remaining.fetch(:gumroad_tax_cents)].min
    price = gross_refund_amount - platform_tax
    raise FundCart::SettlementError, "invalid_refund_amount" if price > remaining.fetch(:amount_cents)
    fee = [Rational(@purchase.fee_cents * price, @purchase.price_cents).floor, remaining.fetch(:fee_cents)].min
    creator_tax = [Rational(gross_refund_amount * @purchase.tax_cents, @purchase.total_transaction_cents).floor, remaining.fetch(:creator_tax_cents)].min
    Refund.new(total_transaction_cents: gross_refund_amount, amount_cents: price, fee_cents: fee,
               creator_tax_cents: creator_tax, gumroad_tax_cents: platform_tax, refunding_user_id:)
  end

  # Called inside Purchase#refund_purchase!'s transaction, after the ordinary Refund was built.
  def account_for_refund!(operation:, refund:, flow_of_funds:)
    validate_operation!(operation)
    raise FundCart::SettlementError, "refund_operation_already_accounted" if operation.refund_id || operation.state == "completed"
    raise FundCart::SettlementError, "refund_operation_amount_mismatch" unless refund.total_transaction_cents == operation.payload.fetch("gross_subunits")
    operation.update!(refund:)
    if @lot
      retained = retained_processor_fee(refund)
      refund.update!(retained_fee_cents: retained) if retained.positive?
      source_loss!(operation:, net: refund.amount_cents - refund.fee_cents - affiliate_refund_cents(refund), flow_of_funds:, retained_fee: retained)
      refund_affiliate!(refund, flow_of_funds)
    else
      recover_destination!(operation, refund)
    end
    operation.update!(state: "completed", completed_at: Time.current, error_code: nil)
    @cart.refresh_balance_projection!
  end

  def dispute!(dispute:, flow_of_funds:, lost: false)
    return false unless @lot
    gross = flow_of_funds&.issued_amount&.cents&.abs
    operation = @cart.with_lock do
      key = "source-dispute:#{@lot.id}:#{dispute.id}"
      original = operations.lock.find_by(operation_key: key)
      if original&.state == "completed"
        return true unless lost
        latest_loss = operations.where(dispute:, kind: "source_dispute", state: "completed").order(id: :desc).lock.first!
        restoration = operations.lock.find_by(operation_key: "restore:#{latest_loss.operation_key}", state: "completed")
        return true unless restoration
        key = "source-dispute-lost:#{@lot.id}:#{dispute.id}:#{restoration.id}"
        original = operations.lock.find_by(operation_key: key)
      end
      freeze_source!(nil)
      original || operations.create!(fund_cart: @cart, fund_cart_funding_lot: @lot, purchase: @purchase, dispute:,
                                     kind: "source_dispute", state: "processing", operation_key: key, payload: {})
    end
    raise FundCart::SettlementError, "source_dispute_amount_unverified" unless gross.is_a?(Integer) && gross.positive?
    ensure_flow_currency!(flow_of_funds, gross:)
    unless @lot.reload.confirmed_at?
      operation.update!(state: "pending", payload: operation.payload.merge("gross_subunits" => gross, "currency" => currency, "lost" => lost))
      return false
    end
    @cart.with_lock do
      @lot.reload.lock!
      operation.reload.lock!
      return true if operation.state == "completed"
      @purchase.reload
      raise FundCart::SettlementError, "affiliate_refund_recovery_requires_reconciliation" if @purchase.affiliate_credit_cents.positive?
      gross = flow_of_funds&.issued_amount&.cents&.abs
      unless gross.is_a?(Integer) && gross.positive? && gross <= remaining_gross_subunits
        raise FundCart::SettlementError, "source_dispute_amount_unverified"
      end
      ensure_flow_currency!(flow_of_funds, gross:)
      split = build_refund(gross_refund_amount: gross, refunding_user_id: nil)
      raise FundCart::SettlementError, "source_dispute_split_unverified" unless split
      source_loss!(operation:, net: split.amount_cents - split.fee_cents, flow_of_funds:)
      operation.update!(state: "completed", completed_at: Time.current)
      @cart.refresh_balance_projection!
    end
    true
  rescue FundCart::SettlementError => error
    operation&.reload&.update!(state: "reconciling", error_code: error.code)
    raise
  end

  def resume_dispute!(operation)
    FundCart::ContributeService.confirm!(lot: @lot, for_reversal: true)
    flow = FlowOfFunds.build_simple_flow_of_funds(operation.payload.fetch("currency"), -operation.payload.fetch("gross_subunits"))
    dispute!(dispute: operation.dispute, flow_of_funds: flow, lost: operation.payload.fetch("lost"))
  end

  def dispute_won!(dispute:, flow_of_funds:)
    return false unless @lot
    @cart.with_lock do
      @lot.reload.lock!
      original = operations.where(dispute:, kind: "source_dispute", state: "completed").order(id: :desc).lock.first!
      ensure_flow_currency!(flow_of_funds, gross: original.payload.fetch("gross_subunits"), direction: 1)
      restore_source!(original, reason: "dispute_won")
      @cart.refresh_balance_projection!
    end
    true
  end

  # The ordinary failed-refund handler still owns flags, fee/affiliate offsets and its exception queue.
  # Acquire the cart before its purchase lock so restoration cannot deadlock an allocation.
  def with_failed_refund_lock(&block)
    @cart.with_lock(&block)
  end

  def refresh_after_failure!
    thaw_source!
  end

  def record_external_refund_id!(processor_refund_id:)
    return unresolved_external_refund! if !@lot || processor_refund_id.blank?
    event = ChargeEvent.new
    event.charge_id = @lot.source_payment_id
    event.refund_id = processor_refund_id
    receive_event!(event, defer_lookup: ApplicationRecord.connection.transaction_open?)
  end

  def record_external_refund!(flow_of_funds:, processor_refund:, refunding_user_id:, is_for_fraud:, note:)
    return unresolved_external_refund! unless @lot && processor_refund&.id.present?
    record_external_refund_id!(processor_refund_id: processor_refund.id)
  end

  def reverse_failed!(refund:)
    return unless @lot
    @lot.reload.lock!
    original = operations.lock.find_by!(refund:, kind: "source_refund", state: "completed")
    settled_currency = original.payload.dig("flow_of_funds", "settled_amount", "currency")
    raise FundCart::SettlementError, "failed_refund_custody_currency_unverified" if settled_currency && settled_currency != currency
    restore_source!(original, reason: "failed_refund")
  end

  private
    def unresolved_external_refund!
      @cart.with_lock do
        freeze_source!(nil) if @lot
        operations.find_or_create_by!(operation_key: "unidentified-source-reversal:#{@purchase.id}") do |operation|
          operation.assign_attributes(fund_cart: @cart, fund_cart_funding_lot: @lot, fund_cart_settlement: @settlement, purchase: @purchase,
                                      kind: "unidentified_reversal", state: "reconciling", error_code: "refund_provider_identity_missing")
        end
      end
      @purchase.errors.add(:base, "Fund cart refund requires a verified original-payment refund reference.")
      false
    end

    def operations
      FundCartSettlementOperation.where(purchase_id: @purchase.id)
    end

    def currency = (@lot || @settlement).currency
    def exponent = (@lot || @settlement).currency_exponent
    def remaining_price_subunits = @purchase.price_cents - @purchase.refunds.effective.sum(:amount_cents)
    def remaining_gross_subunits = @purchase.total_transaction_cents - @purchase.refunds.effective.sum(:total_transaction_cents)

    def authorize!(user_id, reason, fraud)
      user = User.find(user_id) if user_id
      if user&.is_team_member? && user_id != @purchase.seller_id && !fraud && reason.blank?
        raise FundCart::SettlementError, "refund_reason_required"
      end
      raise FundCart::SettlementError, "refunds_disabled" if !user&.is_team_member? && @purchase.seller.refunds_disabled?
    end

    def validate_request!(operation, amount_cents:, tax_only:)
      unless operation.payload["requested_amount_subunits"] == amount_cents && operation.payload["tax_only"] == tax_only
        raise FundCart::SettlementError, "refund_operation_request_mismatch"
      end
    end

    def validate_operation!(operation, allow_missing_evidence: false)
      unless operation.purchase_id == @purchase.id && operation.fund_cart_id == @cart.id && operation.kind.in?(REFUND_KINDS)
        raise FundCart::SettlementError, "wrong_refund_operation"
      end
      return if allow_missing_evidence && @lot && operation.payload.blank?
      raise FundCart::SettlementError, "refund_currency_mismatch" unless operation.payload["currency"] == currency && operation.payload["currency_exponent"] == exponent && currency == Currency.base
    end

    def ensure_source_route!
      account = @lot.source_merchant_account
      # Do not resolve today's merchant or fall back across accounts after disconnection.
      unless account&.stripe_charge_processor? && account.active? && account.is_managed_by_operator? && account.holder_of_funds == HolderOfFunds::GUMROAD &&
          MerchantAccount.operator(account.charge_processor_id)&.id == account.id &&
          (@purchase.charge&.merchant_account_id || @purchase.merchant_account_id) == account.id &&
          @lot.custody_key == "stripe:#{account.id}:#{account.charge_processor_merchant_id}" && @lot.source_payment_id.present? &&
          @lot.native_currency == currency && @lot.canonical_currency == currency && @lot.native_currency_exponent == exponent &&
          @lot.canonical_currency_exponent == exponent
        raise FundCart::SettlementError, "source_refund_route_unverified"
      end
    end

    def ensure_flow_currency!(flow, gross:, direction: -1)
      amounts = [flow&.issued_amount, flow&.settled_amount, flow&.gumroad_amount]
      unless amounts.all? { |amount| amount && amount.currency == currency && amount.cents == gross * direction }
        raise FundCart::SettlementError, "refund_issued_currency_or_amount_mismatch"
      end
    end

    def observe!(operation, response)
      unless response.charge == @lot.source_payment_id && response.currency == currency && response.amount == operation.payload.fetch("gross_subunits")
        raise FundCart::SettlementError, "source_refund_evidence_mismatch"
      end
      if Refund::TERMINAL_FAILURE_STATUSES.include?(response.status)
        if operation.reload.refund_id
          Purchase::HandleFailedRefundService.new(refund: operation.refund, failure_status: response.status).perform
        else
          @cart.with_lock do
            operation.reload.lock!
            operation.update!(state: "failed", error_code: "provider_refund_#{response.status}")
            thaw_source!
          end
        end
        return false
      end
      return true if operation.reload.state == "completed"
      return false if operation.state.in?(%w[failed cancelled])
      unless response.status == "succeeded"
        operation.update!(state: "reconciling", error_code: "provider_refund_pending")
        return false
      end
      balance_transaction = response.balance_transaction
      if balance_transaction.is_a?(String) || balance_transaction.nil?
        operation.update!(state: "reconciling", error_code: "refund_settlement_evidence_pending")
        return false
      end
      operation.update!(payload: operation.payload.merge("provider_settlement" => balance_transaction.to_h))
      unless balance_transaction.id.present? && balance_transaction.source == response.id &&
          balance_transaction.currency == currency && balance_transaction.amount == -response.amount
        raise FundCart::SettlementError, "refund_settlement_evidence_mismatch"
      end
      flow = FlowOfFunds.new(issued_amount: FlowOfFunds::Amount.new(currency: response.currency, cents: -response.amount),
                             settled_amount: FlowOfFunds::Amount.new(currency: balance_transaction.currency, cents: balance_transaction.amount),
                             gumroad_amount: FlowOfFunds::Amount.new(currency: balance_transaction.currency, cents: balance_transaction.amount))
      complete!(operation, flow_of_funds: flow, processor_refund: response)
    end

    def freeze_source!(operation)
      @lot.reload
      @lot.allocations.includes(:fund_cart_settlement).map(&:settlement).uniq.sort_by(&:id).each do |settlement|
        if settlement.state == "reserved"
          FundCart::CancelSettlementService.perform(settlement:, operation_key: "freeze-cancel:#{settlement.operation_key}")
        elsif settlement.state.in?(%w[processing reconciling])
          settlement.update!(cancel_requested_at: Time.current, blocking_reason: "source_reversal_pending")
        end
      end
      @lot.reload.lock!
      @lot.update!(state: "frozen", blocking_reason: "source_reversal_pending")
      operation&.update!(payload: operation.payload.merge("source_merchant_account_id" => @lot.source_merchant_account_id, "owner_id" => @lot.beneficiary_id, "source_payment_id" => @lot.source_payment_id))
      @cart.refresh_balance_projection!
    end

    def thaw_source!
      @lot.reload.lock!
      pending = operations.where(kind: %w[source_refund source_dispute unidentified_reversal], state: %w[pending processing reconciling]).exists?
      if !pending && !@purchase.reload.chargedback_not_reversed? && @lot.debt_subunits.zero?
        @lot.update!(state: @lot.confirmed_at? ? "available" : "pending", blocking_reason: nil)
        if @lot.available_subunits.positive?
          if @lot.confirmation_evidence["availability_verified"] == false
            confirmation = @lot.operations.find_by!(kind: "confirm_source")
            confirmation.update!(state: "pending", available_at: [@lot.available_at, 5.minutes.from_now].max)
          else
            @cart.settlement_operations.find_or_create_by!(operation_key: "allocate-after-reversal:#{@lot.id}:#{@lot.operations.maximum(:id)}") do |operation|
              operation.assign_attributes(kind: "allocate", fund_cart_funding_lot: @lot)
            end
          end
        end
      end
      @cart.refresh_balance_projection!
    end

    def source_dimensions
      { currency:, currency_exponent: exponent, fund_cart_funding_lot_id: @lot.id,
        user_id: @lot.beneficiary_id, merchant_account_id: @lot.source_merchant_account_id }
    end

    def source_loss!(operation:, net:, flow_of_funds:, retained_fee: 0)
      @lot.reload.lock!
      raise FundCart::SettlementError, "source_backing_requires_reconciliation" unless @lot.backed? && @lot.reserved_subunits.zero?
      prior_proceeds = @lot.operations.where(kind: %w[source_refund source_dispute], state: "completed").to_a.sum do |loss|
        operations.exists?(operation_key: "restore:#{loss.operation_key}", state: "completed") ? 0 : loss.payload.fetch("proceeds_subunits", 0)
      end
      raise FundCart::SettlementError, "source_reversal_exceeds_proceeds" unless net >= 0 && net <= @lot.net_subunits - prior_proceeds
      proceeds = net
      net += retained_fee
      gross = operation.payload["gross_subunits"] || flow_of_funds.issued_amount.cents.abs
      ensure_flow_currency!(flow_of_funds, gross:)
      available = [net, @lot.available_subunits].min
      debt = net - available
      postings = [source_dimensions.merge(account: "available", amount_subunits: -available),
                  source_dimensions.merge(account: "owner_debt", amount_subunits: -debt),
                  source_dimensions.merge(account: "source_merchant_liability", amount_subunits: proceeds),
                  source_dimensions.merge(account: "platform_fee", amount_subunits: retained_fee)]
      FundCart::Ledger.post!(operation:, postings:) if net.positive?
      @lot.update!(available_subunits: @lot.available_subunits - available, reversed_subunits: @lot.reversed_subunits + net,
                   debt_subunits: @lot.debt_subunits + debt, state: "frozen", blocking_reason: debt.positive? ? "owner_debt" : "source_reversed")
      operation.update!(payload: operation.payload.merge("net_subunits" => net.to_i, "proceeds_subunits" => proceeds.to_i,
                                                         "retained_fee_subunits" => retained_fee, "debt_remaining" => debt.to_i,
                                                         "gross_subunits" => gross, "currency" => currency, "currency_exponent" => exponent,
                                                         "owner_id" => @lot.beneficiary_id, "source_merchant_account_id" => @lot.source_merchant_account_id,
                                                         "flow_of_funds" => flow_of_funds.to_h))
    end

    def restore_source!(original, reason:)
      key = "restore:#{original.operation_key}"
      return if operations.lock.exists?(operation_key: key)
      net = original.payload.fetch("net_subunits")
      debt = original.payload.fetch("debt_remaining")
      raise FundCart::SettlementError, "source_restore_requires_reconciliation" if debt > @lot.debt_subunits || net > @lot.reversed_subunits
      operation = operations.create!(fund_cart: @cart, fund_cart_funding_lot: @lot, purchase: @purchase, refund: original.refund,
                                     dispute: original.dispute, kind: "source_restore", state: "processing", operation_key: key,
                                     payload: { "original_operation_id" => original.id, "reason" => reason })
      FundCart::Ledger.reverse!(operation:, original_operation: original) if net.positive?
      recovered_debt = -original.ledger_entries.where(account: "owner_debt").sum(:amount_subunits) - debt
      if recovered_debt.positive?
        reclassification = operations.create!(fund_cart: @cart, fund_cart_funding_lot: @lot, purchase: @purchase,
                                              kind: "source_restore_reclassification", operation_key: "reclassify:#{key}", state: "processing",
                                              payload: { "original_operation_id" => original.id, "restoration_operation_id" => operation.id })
        postings = [source_dimensions.merge(account: "owner_debt", amount_subunits: -recovered_debt),
                    source_dimensions.merge(account: "available", amount_subunits: recovered_debt)]
        FundCart::Ledger.post!(operation: reclassification, postings:)
        reclassification.update!(state: "completed", completed_at: Time.current)
      end
      @lot.update!(reversed_subunits: @lot.reversed_subunits - net, debt_subunits: @lot.debt_subunits - debt,
                   available_subunits: @lot.available_subunits + net - debt)
      original.update!(payload: original.payload.merge("debt_remaining" => 0))
      operation.update!(state: "completed", completed_at: Time.current)
      thaw_source!
    end

    def with_accounting_locks(&block)
      balances = []
      if @settlement
        original = @purchase.balance_transactions.find(@settlement.receipt.fetch("seller_balance_transaction_id"))
        balances << original.balance
      end
      if @purchase.affiliate_credit_cents.positive?
        raise FundCart::SettlementError, "affiliate_refund_recovery_requires_reconciliation"
      end
      lock_balances(balances.compact.sort_by(&:id)) do
        @cart.with_lock do
          @settlement&.reload&.lock!
          @lot&.reload&.lock!
          block.call
        end
      end
    end

    def lock_balances(balances, &block)
      return block.call if balances.empty?
      balances.first.with_lock { lock_balances(balances.drop(1), &block) }
    end

    def retained_processor_fee(refund)
      return 0 if refund.is_for_fraud? || refund.amount_cents.zero?
      if @purchase.processor_fee_cents.present? && @purchase.processor_fee_cents_currency == currency
        Rational(@purchase.processor_fee_cents * refund.amount_cents, @purchase.price_cents).round
      else
        (Rational(refund.amount_cents * Purchase::PROCESSOR_FEE_PER_THOUSAND, 1000) +
          Rational(Purchase::PROCESSOR_FIXED_FEE_CENTS * refund.amount_cents, @purchase.price_cents)).round
      end
    end

    def affiliate_refund_cents(refund)
      return 0 if @purchase.affiliate_credit_cents.zero?
      Rational(@purchase.affiliate_credit_cents * refund.amount_cents, @purchase.price_cents).ceil
    end

    def refund_affiliate!(refund, flow)
      return if @purchase.affiliate_credit_cents.zero?
      @purchase.process_refund_or_chargeback_for_affiliate_credit_balance(flow, refund:, refund_cents: affiliate_refund_cents(refund))
    end

    def recover_destination!(operation, refund)
      raise FundCart::SettlementError, "destination_refund_route_unverified" unless @settlement.route == FundCart::Eligibility::ROUTE && @settlement.valid_receipt_for?(@purchase)
      gross = refund.total_transaction_cents
      net = refund.amount_cents - refund.fee_cents
      original = @purchase.balance_transactions.find(@settlement.receipt.fetch("seller_balance_transaction_id"))
      balance = original.balance.reload
      unless balance.unpaid? && balance.currency == currency && balance.holding_currency == currency && balance.amount_cents >= net && balance.holding_amount_cents >= net
        raise FundCart::SettlementError, "destination_seller_recovery_insufficient"
      end
      amount = BalanceTransaction::Amount.new(currency:, gross_cents: -gross, net_cents: -net)
      debit = BalanceTransaction.create!(user: @purchase.seller, merchant_account: @settlement.destination_merchant_account,
                                         refund:, issued_amount: amount, holding_amount: amount, update_user_balance: false)
      balance.update!(amount_cents: balance.amount_cents - net, holding_amount_cents: balance.holding_amount_cents - net)
      debit.update!(balance:)
      @purchase.purchase_refund_balance = balance
      dimensions = { currency:, currency_exponent: exponent, fund_cart_settlement_id: @settlement.id,
                     merchant_account_id: @settlement.destination_merchant_account_id }
      postings = [dimensions.merge(account: "seller_payable", user_id: @purchase.seller_id, amount_subunits: -net),
                  dimensions.merge(account: "platform_fee", amount_subunits: -refund.fee_cents),
                  dimensions.merge(account: "platform_tax", amount_subunits: -refund.gumroad_tax_cents)]
      remaining = gross
      @settlement.allocations.order(:fund_cart_funding_lot_id).lock.each do |allocation|
        lot = allocation.funding_lot
        lot.lock!
        restored = [remaining, allocation.amount_subunits - allocation.reversed_subunits].min
        next unless restored.positive?
        debt = [restored, lot.debt_subunits].min
        remaining_debt = debt
        lot.operations.where(kind: %w[source_refund source_dispute], state: "completed").order(:id).lock.each do |loss|
          recovered = [remaining_debt, loss.payload.fetch("debt_remaining", 0)].min
          next unless recovered.positive?
          loss.update!(payload: loss.payload.merge("debt_remaining" => loss.payload.fetch("debt_remaining") - recovered.to_i))
          remaining_debt -= recovered
        end
        raise FundCart::SettlementError, "owner_debt_identity_missing" unless remaining_debt.zero?
        lot.update!(spent_subunits: lot.spent_subunits - restored, debt_subunits: lot.debt_subunits - debt,
                    available_subunits: lot.available_subunits + restored - debt)
        allocation.update!(reversed_subunits: allocation.reversed_subunits + restored)
        FundCart::RefundService.new(purchase: lot.source_purchase).send(:thaw_source!) if debt.positive? && lot.debt_subunits.zero?
        source = dimensions.merge(fund_cart_funding_lot_id: lot.id, user_id: lot.beneficiary_id, merchant_account_id: lot.source_merchant_account_id)
        postings << source.merge(account: "owner_debt", amount_subunits: debt)
        postings << source.merge(account: "available", amount_subunits: restored - debt)
        remaining -= restored
      end
      raise FundCart::SettlementError, "destination_refund_exceeds_allocations" unless remaining.zero?
      FundCart::Ledger.post!(operation:, postings:)
      @settlement.update!(reversed_subunits: @settlement.reversed_subunits + gross)
      operation.update!(external_references: { "seller_recovery_balance_transaction_id" => debit.id })
    end

    def complete_tax_refund!(operation, processor_refund, flow_of_funds)
      @purchase.reload.lock!
      gross = operation.payload.fetch("gross_subunits")
      raise FundCart::SettlementError, "tax_refund_exceeds_remaining" if gross > @purchase.gumroad_tax_refundable_cents
      refund = @purchase.refunds.create!(total_transaction_cents: gross, amount_cents: 0, creator_tax_cents: 0,
                                         fee_cents: 0, gumroad_tax_cents: gross, refunding_user_id: operation.payload["refunding_user_id"],
                                         processor_refund_id: processor_refund&.id, status: "succeeded",
                                         note: operation.payload["reason"], business_vat_id: operation.payload["business_vat_id"])
      account_for_refund!(operation:, refund:, flow_of_funds:)
      @purchase.save!
      @purchase.subscription&.update_business_vat_id!(operation.payload["business_vat_id"]) if operation.payload["business_vat_id"].present?
      true
    end
end
