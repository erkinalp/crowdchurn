# frozen_string_literal: true

require "ubl"

module ElectronicInvoiceGenerator
  SUPPORTED_FORMATS = %w[pdf ubl peppol].freeze

  class Error < StandardError; end
  class UnsupportedFormatError < Error; end
  class ValidationError < Error; end

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
      else
        raise UnsupportedFormatError, "No generator for format: #{format}"
      end
    end
  end

  class Base
    include CurrencyHelper

    attr_reader :chargeable, :address_fields, :additional_notes, :business_vat_id

    def initialize(chargeable:, address_fields:, additional_notes: nil, business_vat_id: nil)
      @chargeable = chargeable
      @address_fields = address_fields
      @additional_notes = additional_notes
      @business_vat_id = business_vat_id
    end

    def generate
      raise NotImplementedError, "Subclasses must implement #generate"
    end

    def content_type
      "application/xml"
    end

    def file_extension
      "xml"
    end

    protected
      def invoice_presenter
        @invoice_presenter ||= InvoicePresenter.new(
          chargeable,
          address_fields:,
          additional_notes:,
          business_vat_id:
        )
      end

      def supplier_data
        @supplier_data ||= invoice_presenter.supplier_info
      end

      def seller_data
        @seller_data ||= invoice_presenter.seller_info
      end

      def order_data
        @order_data ||= invoice_presenter.order_info
      end

      def invoice_number
        chargeable.external_id_numeric_for_invoice
      end

      def invoice_date
        chargeable.orderable.created_at.to_date
      end

      def due_date
        invoice_date + 30.days
      end

      def currency_code
        "USD"
      end

      def supplier_name
        "Gumroad, Inc."
      end

      def supplier_country_code
        GumroadAddress::COUNTRY.alpha2
      end

      def supplier_address
        GumroadAddress::STREET
      end

      def supplier_city
        GumroadAddress::CITY
      end

      def supplier_postal_code
        GumroadAddress::ZIP_PLUS_FOUR
      end

      def supplier_vat_id
        gumroad_vat_registration_number
      end

      def gumroad_vat_registration_number
        country_code = customer_country_code
        if Compliance::Countries::EU_VAT_APPLICABLE_COUNTRY_CODES.include?(country_code)
          GUMROAD_VAT_REGISTRATION_NUMBER
        elsif country_code == Compliance::Countries::AUS.alpha2
          GUMROAD_AUSTRALIAN_BUSINESS_NUMBER
        elsif country_code == Compliance::Countries::CAN.alpha2
          GUMROAD_CANADA_GST_REGISTRATION_NUMBER
        elsif country_code == Compliance::Countries::NOR.alpha2
          GUMROAD_NORWAY_VAT_REGISTRATION
        else
          GUMROAD_OTHER_TAX_REGISTRATION
        end
      end

      def customer_name
        address_fields[:full_name].presence || chargeable.full_name&.strip.presence || chargeable.purchaser&.name || "Customer"
      end

      def customer_country_code
        @customer_country_code ||= begin
          country_name = address_fields[:country].presence || chargeable.country_or_ip_country
          Compliance::Countries.find_by_name(country_name)&.alpha2 || "US"
        end
      end

      def customer_address
        address_fields[:street_address].presence || chargeable.street_address
      end

      def customer_city
        address_fields[:city].presence || chargeable.city
      end

      def customer_postal_code
        address_fields[:zip_code].presence || chargeable.zip_code
      end

      def customer_vat_id
        business_vat_id || chargeable.purchase_sales_tax_info&.business_vat_id
      end

      def invoice_lines_data
        @invoice_lines_data ||= chargeable.successful_purchases.map do |purchase|
          next if purchase.is_free_trial_purchase?

          line_amount_cents = purchase.displayed_price_cents
          line_amount = cents_to_dollars(line_amount_cents)
          tax_amount_cents = purchase.non_refunded_tax_amount
          tax_rate = calculate_tax_rate(purchase)

          {
            name: purchase.link.name,
            description: purchase.link.name,
            quantity: purchase.quantity,
            unit_price: line_amount / purchase.quantity,
            line_extension_amount: line_amount,
            tax_rate: tax_rate,
            tax_amount: cents_to_dollars(tax_amount_cents)
          }
        end.compact
      end

      def total_line_extension_amount
        invoice_lines_data.sum { |line| line[:line_extension_amount] }
      end

      def total_tax_amount
        invoice_lines_data.sum { |line| line[:tax_amount] }
      end

      def total_payable_amount
        total_line_extension_amount + total_tax_amount + shipping_amount
      end

      def shipping_amount
        cents_to_dollars(chargeable.successful_purchases.sum { |p| p.is_free_trial_purchase? ? 0 : p.shipping_cents })
      end

      def cents_to_dollars(cents)
        (cents.to_f / 100).round(2)
      end

      def calculate_tax_rate(purchase)
        return 0.0 if purchase.non_refunded_tax_amount.zero? || purchase.displayed_price_cents.zero?

        ((purchase.non_refunded_tax_amount.to_f / purchase.displayed_price_cents) * 100).round(2)
      end
  end

  class Ubl < Base
    def generate
      invoice = ::Ubl::Invoice.new
      configure_invoice(invoice)
      invoice.build
    end

    protected
      def configure_invoice(invoice)
        invoice.invoice_nr = invoice_number
        invoice.issue_date = invoice_date
        invoice.due_date = due_date
        invoice.currency = currency_code

        add_supplier_to_invoice(invoice)
        add_customer_to_invoice(invoice)
        add_invoice_lines(invoice)
      end

      def add_supplier_to_invoice(invoice)
        invoice.add_supplier(
          name: supplier_name,
          country: supplier_country_code,
          vat_id: supplier_vat_id,
          address: supplier_address,
          city: supplier_city,
          postal_code: supplier_postal_code
        )
      end

      def add_customer_to_invoice(invoice)
        invoice.add_customer(
          name: customer_name,
          country: customer_country_code,
          vat_id: customer_vat_id,
          address: customer_address,
          city: customer_city,
          postal_code: customer_postal_code
        )
      end

      def add_invoice_lines(invoice)
        invoice_lines_data.each do |line|
          invoice.add_line(
            name: line[:name],
            description: line[:description],
            quantity: line[:quantity],
            unit_price: line[:unit_price],
            tax_rate: line[:tax_rate]
          )
        end
      end
  end

  class Peppol < Ubl
    def generate
      invoice = ::Ubl::Invoice.new
      configure_invoice(invoice)
      invoice.build
    end
  end
end
