# frozen_string_literal: true

module ElectronicInvoiceGenerator
  class Xrechnung < Ubl
    XRECHNUNG_CUSTOMIZATION_ID = "urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0"
    XRECHNUNG_PROFILE_ID = "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"

    protected
      def configure_invoice(invoice)
        super
        invoice.customization_id = XRECHNUNG_CUSTOMIZATION_ID if invoice.respond_to?(:customization_id=)
        invoice.profile_id = XRECHNUNG_PROFILE_ID if invoice.respond_to?(:profile_id=)
      end

      def add_customer_to_invoice(invoice)
        super
        add_leitweg_id(invoice) if leitweg_id.present?
      end

      def leitweg_id
        address_fields[:leitweg_id]
      end

      def add_leitweg_id(invoice)
        invoice.buyer_reference = leitweg_id if invoice.respond_to?(:buyer_reference=)
      end
  end
end
