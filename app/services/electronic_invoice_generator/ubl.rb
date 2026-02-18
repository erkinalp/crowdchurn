# frozen_string_literal: true

module ElectronicInvoiceGenerator
  class Ubl < Base
    def generate
      validate_required_data!
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
end
