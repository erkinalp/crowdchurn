# frozen_string_literal: true

class HandleKillbillEventWorker
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 3

  def perform(killbill_event)
    KillbillChargeProcessor.handle_killbill_event(killbill_event)
  end
end
