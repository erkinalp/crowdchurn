# frozen_string_literal: true

module ElectronicInvoiceGenerator
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
      validate_required_data!
      raise NotImplementedError, "Subclasses must implement #generate"
    end

    def content_type
      "application/xml"
    end

    def validate_required_data!
      errors = []
      errors << "Customer name is required" if presenter_data[:customer][:name].blank? || presenter_data[:customer][:name] == "Customer"
      errors << "Customer country is required" if presenter_data[:customer][:country_code].blank?
      errors << "No invoice line items found" if presenter_data[:line_items].empty?

      Rails.logger.warn("Invoice #{presenter_data[:invoice_number]}: Customer address is incomplete") if presenter_data[:customer][:address].blank?
      Rails.logger.warn("Invoice #{presenter_data[:invoice_number]}: Customer city is missing") if presenter_data[:customer][:city].blank?
      Rails.logger.warn("Invoice #{presenter_data[:invoice_number]}: Customer postal code is missing") if presenter_data[:customer][:postal_code].blank?

      raise MissingDataError, errors.join("; ") if errors.any?
    end

    def file_extension
      "xml"
    end

    protected
      def presenter_data
        @presenter_data ||= invoice_presenter.electronic_invoice_data
      end

      def invoice_presenter
        @invoice_presenter ||= InvoicePresenter.new(
          chargeable,
          address_fields:,
          additional_notes:,
          business_vat_id:
        )
      end

      def invoice_number
        presenter_data[:invoice_number]
      end

      def invoice_date
        presenter_data[:invoice_date]
      end

      def due_date
        invoice_date + 30.days
      end

      def currency_code
        presenter_data[:currency_code]
      end

      def supplier_name
        presenter_data[:supplier][:name]
      end

      def supplier_country_code
        presenter_data[:supplier][:country_code]
      end

      def supplier_address
        presenter_data[:supplier][:address]
      end

      def supplier_city
        presenter_data[:supplier][:city]
      end

      def supplier_postal_code
        presenter_data[:supplier][:postal_code]
      end

      def supplier_vat_id
        presenter_data[:supplier][:vat_id]
      end

      def supplier_email
        PLATFORM_SUPPLIER_EMAIL
      end

      def supplier_website
        PLATFORM_SUPPLIER_WEBSITE
      end

      def customer_name
        presenter_data[:customer][:name]
      end

      def customer_country_code
        presenter_data[:customer][:country_code]
      end

      def customer_address
        presenter_data[:customer][:address]
      end

      def customer_city
        presenter_data[:customer][:city]
      end

      def customer_postal_code
        presenter_data[:customer][:postal_code]
      end

      def customer_vat_id
        presenter_data[:customer][:vat_id]
      end

      def invoice_lines_data
        @invoice_lines_data ||= presenter_data[:line_items].map do |item|
          unit_price = subunits_to_units(item[:unit_price_cents])
          line_amount = subunits_to_units(item[:line_extension_cents])
          tax_amount = subunits_to_units(item[:tax_cents])

          {
            name: item[:name],
            description: item[:description],
            quantity: item[:quantity],
            unit_price: unit_price,
            line_extension_amount: line_amount,
            tax_rate: item[:tax_rate],
            tax_amount: tax_amount
          }
        end
      end

      def total_line_extension_amount
        subunits_to_units(presenter_data[:totals][:line_extension_amount_cents])
      end

      def total_tax_amount
        subunits_to_units(presenter_data[:totals][:tax_amount_cents])
      end

      def total_payable_amount
        subunits_to_units(presenter_data[:totals][:payable_amount_cents])
      end

      def shipping_amount
        subunits_to_units(presenter_data[:totals][:shipping_cents])
      end

      def subunits_to_units(subunits)
        factor = subunit_to_unit_factor
        (subunits.to_f / factor).round(2)
      end

      def subunit_to_unit_factor
        @subunit_to_unit_factor ||= begin
          code = currency_code.to_s.downcase
          if is_currency_type_single_unit?(code)
            1
          else
            100
          end
        end
      end
  end
end
