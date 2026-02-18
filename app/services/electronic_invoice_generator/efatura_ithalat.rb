# frozen_string_literal: true

module ElectronicInvoiceGenerator
  class EfaturaIthalat < Base
    SCENARIO_TYPE = "ITHALAT"
    INVOICE_TYPE_CODE = "SATIS"
    UBL_TR_NAMESPACE = "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
    UBL_TR_COMMON_NAMESPACE = "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
    UBL_TR_AGGREGATE_NAMESPACE = "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"

    def generate
      validate_required_data!
      build_ubl_tr_invoice
    end

    protected
      def build_ubl_tr_invoice
        builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml.Invoice(xmlns: UBL_TR_NAMESPACE,
                      "xmlns:cbc" => UBL_TR_COMMON_NAMESPACE,
                      "xmlns:cac" => UBL_TR_AGGREGATE_NAMESPACE) do
            build_invoice_header(xml)
            build_accounting_supplier_party(xml)
            build_accounting_customer_party(xml)
            build_tax_total(xml)
            build_legal_monetary_total(xml)
            build_invoice_lines(xml)
          end
        end
        builder.to_xml
      end

      def build_invoice_header(xml)
        xml["cbc"].UBLVersionID "2.1"
        xml["cbc"].CustomizationID scenario_customization_id
        xml["cbc"].ProfileID SCENARIO_TYPE
        xml["cbc"].ID invoice_number
        xml["cbc"].CopyIndicator "false"
        xml["cbc"].UUID deterministic_uuid
        xml["cbc"].IssueDate invoice_date.strftime("%Y-%m-%d")
        xml["cbc"].IssueTime Time.current.strftime("%H:%M:%S")
        xml["cbc"].InvoiceTypeCode INVOICE_TYPE_CODE
        xml["cbc"].Note additional_notes if additional_notes.present?
        xml["cbc"].DocumentCurrencyCode currency_code
        xml["cbc"].LineCountNumeric invoice_lines_data.count
      end

      def deterministic_uuid
        Digest::UUID.uuid_v5(Digest::UUID::DNS_NAMESPACE, "efatura-#{chargeable.class.name}-#{chargeable.id}-#{invoice_number}")
      end

      def build_accounting_supplier_party(xml)
        xml["cac"].AccountingSupplierParty do
          xml["cac"].Party do
            xml["cbc"].WebsiteURI supplier_website
            build_party_identification(xml, supplier_vat_id)
            build_party_name(xml, supplier_name)
            build_postal_address(xml, supplier_address, supplier_city, supplier_postal_code, supplier_country_code)
            build_party_tax_scheme(xml, supplier_vat_id)
            build_party_legal_entity(xml, supplier_name)
            build_contact(xml)
          end
        end
      end

      def build_accounting_customer_party(xml)
        xml["cac"].AccountingCustomerParty do
          xml["cac"].Party do
            build_party_identification(xml, customer_vat_id) if customer_vat_id.present?
            build_party_name(xml, customer_name)
            build_postal_address(xml, customer_address, customer_city, customer_postal_code, customer_country_code)
            build_party_tax_scheme(xml, customer_vat_id) if customer_vat_id.present?
            build_party_legal_entity(xml, customer_name)
          end
        end
      end

      def build_party_identification(xml, id)
        return unless id.present?

        xml["cac"].PartyIdentification do
          xml["cbc"].ID(schemeID: "VKN") { xml.text id }
        end
      end

      def build_party_name(xml, name)
        xml["cac"].PartyName do
          xml["cbc"].Name name
        end
      end

      def build_postal_address(xml, street, city, postal_code, country_code)
        xml["cac"].PostalAddress do
          xml["cbc"].StreetName street if street.present?
          xml["cbc"].CityName city if city.present?
          xml["cbc"].PostalZone postal_code if postal_code.present?
          xml["cac"].Country do
            xml["cbc"].IdentificationCode country_code
          end
        end
      end

      def build_party_tax_scheme(xml, tax_id)
        xml["cac"].PartyTaxScheme do
          xml["cbc"].CompanyID tax_id if tax_id.present?
          xml["cac"].TaxScheme do
            xml["cbc"].Name "VAT"
          end
        end
      end

      def build_party_legal_entity(xml, name)
        xml["cac"].PartyLegalEntity do
          xml["cbc"].RegistrationName name
        end
      end

      def build_contact(xml)
        xml["cac"].Contact do
          xml["cbc"].ElectronicMail supplier_email
        end
      end

      def build_tax_total(xml)
        xml["cac"].TaxTotal do
          xml["cbc"].TaxAmount(currencyID: currency_code) { xml.text format_amount(total_tax_amount) }
          invoice_lines_data.group_by { |l| l[:tax_rate] }.each do |_rate, lines|
            tax_amount = lines.sum { |l| l[:tax_amount] }
            taxable_amount = lines.sum { |l| l[:line_extension_amount] }
            xml["cac"].TaxSubtotal do
              xml["cbc"].TaxableAmount(currencyID: currency_code) { xml.text format_amount(taxable_amount) }
              xml["cbc"].TaxAmount(currencyID: currency_code) { xml.text format_amount(tax_amount) }
              xml["cac"].TaxCategory do
                xml["cac"].TaxScheme do
                  xml["cbc"].Name "KDV"
                  xml["cbc"].TaxTypeCode "0015"
                end
              end
            end
          end
        end
      end

      def build_legal_monetary_total(xml)
        xml["cac"].LegalMonetaryTotal do
          xml["cbc"].LineExtensionAmount(currencyID: currency_code) { xml.text format_amount(total_line_extension_amount) }
          xml["cbc"].TaxExclusiveAmount(currencyID: currency_code) { xml.text format_amount(total_line_extension_amount) }
          xml["cbc"].TaxInclusiveAmount(currencyID: currency_code) { xml.text format_amount(total_payable_amount) }
          xml["cbc"].PayableAmount(currencyID: currency_code) { xml.text format_amount(total_payable_amount) }
        end
      end

      def build_invoice_lines(xml)
        invoice_lines_data.each_with_index do |line, index|
          xml["cac"].InvoiceLine do
            xml["cbc"].ID (index + 1).to_s
            xml["cbc"].InvoicedQuantity(unitCode: "C62") { xml.text line[:quantity].to_s }
            xml["cbc"].LineExtensionAmount(currencyID: currency_code) { xml.text format_amount(line[:line_extension_amount]) }
            build_line_tax_total(xml, line)
            xml["cac"].Item do
              xml["cbc"].Name line[:name]
            end
            xml["cac"].Price do
              xml["cbc"].PriceAmount(currencyID: currency_code) { xml.text format_amount(line[:unit_price]) }
            end
          end
        end
      end

      def build_line_tax_total(xml, line)
        xml["cac"].TaxTotal do
          xml["cbc"].TaxAmount(currencyID: currency_code) { xml.text format_amount(line[:tax_amount]) }
          xml["cac"].TaxSubtotal do
            xml["cbc"].TaxableAmount(currencyID: currency_code) { xml.text format_amount(line[:line_extension_amount]) }
            xml["cbc"].TaxAmount(currencyID: currency_code) { xml.text format_amount(line[:tax_amount]) }
            xml["cbc"].Percent line[:tax_rate].to_s
            xml["cac"].TaxCategory do
              xml["cac"].TaxScheme do
                xml["cbc"].Name "KDV"
                xml["cbc"].TaxTypeCode "0015"
              end
            end
          end
        end
      end

      def scenario_customization_id
        "TR1.2.1"
      end

      def format_amount(amount)
        format("%.2f", amount)
      end
  end
end
