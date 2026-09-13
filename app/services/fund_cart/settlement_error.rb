# frozen_string_literal: true

class FundCart::SettlementError < StandardError
  attr_reader :code

  def initialize(code)
    @code = code
    super(code.to_s)
  end
end
