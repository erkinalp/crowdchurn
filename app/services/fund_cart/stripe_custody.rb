# frozen_string_literal: true

class FundCart::StripeCustody
  # This adapter proves a captured platform balance credit; it does not claim authority over Connect accounts.
  def self.confirm(lot:, for_reversal: false)
    raise FundCart::SettlementError, "external_request_inside_transaction" if ApplicationRecord.connection.transaction_open?
    purchase = lot.source_purchase
    account = purchase.charge&.merchant_account || purchase.merchant_account
    result = FundCart::Eligibility.account_result(account).ensure_supported!
    raise FundCart::SettlementError, "custody_changed" unless result.custody_key == lot.custody_key
    payment_id = purchase.charge&.processor_transaction_id || purchase.stripe_transaction_id
    raise FundCart::SettlementError, "source_payment_missing" if payment_id.blank?

    charge = Stripe::Charge.retrieve(id: payment_id, expand: ["balance_transaction"])
    evidence_for(lot:, charge:, payment_id:, result:, for_reversal:)
  end

  def self.evidence_for(lot:, charge:, payment_id:, result:, for_reversal: false)
    purchase = lot.source_purchase
    balance = charge[:balance_transaction]
    expected_gross = purchase.charge&.amount_cents || purchase.total_transaction_cents
    purchases = purchase.charge ? purchase.charge.purchases.to_a : [purchase]
    refunded_subunits = purchases.sum { |source| source.refunds.effective.sum(:total_transaction_cents) }
    valid = charge[:id] == payment_id && charge[:status] == "succeeded" && charge[:paid] == true && charge[:captured] == true &&
      charge[:amount] == expected_gross && charge[:amount_captured] == expected_gross &&
      charge[:currency] == lot.currency &&
      (for_reversal || (charge[:refunded] == false && charge[:amount_refunded] == refunded_subunits && charge[:disputed] == false && charge[:dispute].blank?)) &&
      charge[:destination].blank? &&
      charge[:transfer].blank? && charge[:transfer_data].blank? && charge[:application_fee].blank? &&
      charge[:on_behalf_of].blank? && (balance.is_a?(Hash) || balance.is_a?(Stripe::BalanceTransaction))
    raise FundCart::SettlementError, "source_capture_unconfirmed" unless valid
    valid_balance = balance[:id].present? && balance[:source] == payment_id && balance[:currency] == lot.currency &&
      balance[:status].in?(%w[pending available]) && balance[:available_on].is_a?(Integer) && balance[:available_on].positive? &&
      %i[amount net fee].all? { |field| balance[field].is_a?(Integer) } &&
      balance[:amount] == expected_gross && balance[:net] == balance[:amount] - balance[:fee] &&
      balance[:net] >= 0 && balance[:fee] >= 0
    raise FundCart::SettlementError, "source_balance_unconfirmed" unless valid_balance
    raise FundCart::SettlementError, "source_not_yet_available" if !for_reversal && (balance[:status] == "pending" || balance[:available_on] > Time.current.to_i)

    # For combined charges preserve the exact source portion; never credit the whole charge to each lot.
    raise FundCart::SettlementError, "source_charge_allocation_mismatch" unless purchases.sum(&:total_transaction_cents) == expected_gross
    obligations = purchases.sum { |source| source.total_transaction_cents - source.fee_cents }
    raise FundCart::SettlementError, "source_net_insufficient" if balance[:net] < obligations || lot.net_subunits > purchase.payment_cents - purchase.affiliate_credit_cents
    {
      "payment_id" => payment_id, "balance_transaction_id" => balance[:id],
      "custody_key" => result.custody_key, "currency" => charge[:currency], "currency_exponent" => 2,
      "charge_gross_subunits" => charge[:amount], "charge_net_subunits" => balance[:net], "processor_fee_subunits" => balance[:fee],
      "source_gross_subunits" => purchase.total_transaction_cents, "source_net_subunits" => lot.net_subunits.to_i,
      "available_at" => Time.zone.at(balance[:available_on]).iso8601, "confirmed_at" => Time.current.iso8601,
      "availability_verified" => balance[:status] == "available" && balance[:available_on] <= Time.current.to_i
    }
  end
end
