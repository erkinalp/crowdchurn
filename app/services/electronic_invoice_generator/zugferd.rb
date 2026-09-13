# frozen_string_literal: true

module ElectronicInvoiceGenerator
  class Zugferd < Base
    ZUGFERD_PROFILE = :EN16931

    def generate
      validate_required_data!
      build_cii_invoices.map { |inv| inv.to_xml(version: 2) }.join
    end

    protected
      def build_cii_invoices
        tax_groups = invoice_lines_data.group_by { |l| l[:tax_rate] }

        if tax_groups.size <= 1
          rate = tax_groups.keys.first || 0.0
          category = rate.positive? ? :STANDARDRATE : :ZEROTAXPRODUCTS
          return [build_single_cii_invoice(category, rate.to_s)]
        end

        tax_groups.map do |rate, lines|
          category = rate.positive? ? :STANDARDRATE : :ZEROTAXPRODUCTS
          tax_amount = lines.sum { |l| l[:tax_amount] }
          basis_amount = lines.sum { |l| l[:line_extension_amount] }
          grand_total = basis_amount + tax_amount

          line_items = lines.each_with_index.map do |line, _index|
            Secretariat::LineItem.new(
              name: line[:name],
              quantity: line[:quantity],
              unit_code: "C62",
              gross_amount: line[:line_extension_amount].to_s,
              net_amount: line[:line_extension_amount].to_s,
              charge_amount: line[:unit_price].to_s,
              tax_category: category,
              tax_percent: line[:tax_rate].to_s,
              origin_country_code: supplier_country_code
            )
          end

          Secretariat::Invoice.new(
            id: invoice_number,
            issue_date: invoice_date,
            currency_code: currency_code,
            seller: build_seller,
            buyer: build_buyer,
            line_items: line_items,
            payment_type: :BANKACCOUNT,
            payment_text: payment_text,
            tax_category: category,
            tax_percent: rate.to_s,
            tax_amount: tax_amount.to_s,
            basis_amount: basis_amount.to_s,
            grand_total_amount: grand_total.to_s,
            due_amount: grand_total.to_s,
            paid_amount: "0"
          )
        end
      end

      def build_single_cii_invoice(category, rate_str)
        Secretariat::Invoice.new(
          id: invoice_number,
          issue_date: invoice_date,
          currency_code: currency_code,
          seller: build_seller,
          buyer: build_buyer,
          line_items: build_line_items(category),
          payment_type: :BANKACCOUNT,
          payment_text: payment_text,
          tax_category: category,
          tax_percent: rate_str,
          tax_amount: total_tax_amount.to_s,
          basis_amount: total_line_extension_amount.to_s,
          grand_total_amount: total_payable_amount.to_s,
          due_amount: total_payable_amount.to_s,
          paid_amount: "0"
        )
      end

      def build_seller
        Secretariat::TradeParty.new(
          name: supplier_name,
          street1: supplier_address,
          city: supplier_city,
          postal_code: supplier_postal_code,
          country_id: supplier_country_code,
          vat_id: supplier_vat_id
        )
      end

      def build_buyer
        Secretariat::TradeParty.new(
          name: customer_name,
          street1: customer_address,
          city: customer_city,
          postal_code: customer_postal_code,
          country_id: customer_country_code,
          vat_id: customer_vat_id
        )
      end

      def build_line_items(category)
        invoice_lines_data.map do |line|
          Secretariat::LineItem.new(
            name: line[:name],
            quantity: line[:quantity],
            unit_code: "C62",
            gross_amount: line[:line_extension_amount].to_s,
            net_amount: line[:line_extension_amount].to_s,
            charge_amount: line[:unit_price].to_s,
            tax_category: category,
            tax_percent: line[:tax_rate].to_s,
            origin_country_code: supplier_country_code
          )
        end
      end

      def payment_text
        "Payment for invoice #{invoice_number}"
      end
  end
end
