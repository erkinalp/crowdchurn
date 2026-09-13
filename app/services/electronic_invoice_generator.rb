# frozen_string_literal: true

require "ubl"
require "secretariat"

module ElectronicInvoiceGenerator
  SUPPORTED_FORMATS = %w[pdf ubl peppol xrechnung zugferd efatura_ithalat].freeze

  class Error < StandardError; end
  class UnsupportedFormatError < Error; end
  class ValidationError < Error; end
  class MissingDataError < Error; end

  class << self
    def generate(format:, chargeable:, address_fields:, additional_notes: nil, business_vat_id: nil)
      raise UnsupportedFormatError, "Unsupported format: #{format}" unless SUPPORTED_FORMATS.include?(format.to_s)

      generator = generator_for(format)
      generator.new(
        chargeable:,
        address_fields:,
        additional_notes:,
        business_vat_id:
      ).generate
    end

    def generator_for(format)
      case format.to_s
      when "ubl"
        Ubl
      when "peppol"
        Peppol
      when "xrechnung"
        Xrechnung
      when "zugferd"
        Zugferd
      when "efatura_ithalat"
        EfaturaIthalat
      else
        raise UnsupportedFormatError, "No generator for format: #{format}"
      end
    end
  end
end
