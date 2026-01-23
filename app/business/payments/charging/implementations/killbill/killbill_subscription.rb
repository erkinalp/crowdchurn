# frozen_string_literal: true

class KillbillSubscription
  attr_reader :subscription

  delegate :subscription_id, :account_id, :bundle_id, :external_key,
           :start_date, :charged_through_date, :cancelled_date,
           :plan_name, :product_name, :billing_period, :phase_type,
           :price_list, to: :subscription, allow_nil: true

  def initialize(subscription)
    @subscription = subscription
  end

  def id
    subscription_id
  end

  def state
    return "CANCELLED" if cancelled_date.present?
    return "PENDING" if start_date.present? && start_date > Time.current

    subscription.state || "ACTIVE"
  end

  def active?
    state == "ACTIVE"
  end

  def cancelled?
    state == "CANCELLED"
  end

  def pending?
    state == "PENDING"
  end

  def blocked?
    state == "BLOCKED"
  end

  def current_phase
    phase_type
  end

  def next_billing_date
    charged_through_date
  end

  def recurrence
    case billing_period&.upcase
    when "MONTHLY"
      BasePrice::Recurrence::MONTHLY
    when "ANNUAL"
      BasePrice::Recurrence::YEARLY
    when "QUARTERLY"
      BasePrice::Recurrence::QUARTERLY
    when "WEEKLY"
      BasePrice::Recurrence::WEEKLY
    else
      BasePrice::Recurrence::MONTHLY
    end
  end

  def to_h
    {
      id: subscription_id,
      account_id: account_id,
      bundle_id: bundle_id,
      external_key: external_key,
      state: state,
      plan_name: plan_name,
      product_name: product_name,
      billing_period: billing_period,
      phase_type: phase_type,
      start_date: start_date,
      charged_through_date: charged_through_date,
      cancelled_date: cancelled_date
    }
  end
end
