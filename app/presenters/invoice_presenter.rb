# frozen_string_literal: true

class InvoicePresenter
  def initialize(chargeable, address_fields: {}, additional_notes: nil, business_vat_id: nil)
    @chargeable = chargeable
    @address_fields = address_fields
    @additional_notes = additional_notes
    @business_vat_id = business_vat_id
  end

  def invoice_generation_props
    form_info = InvoicePresenter::FormInfo.new(chargeable)

    {
      form_info: {
        heading: form_info.heading,
        display_vat_id: form_info.display_vat_id?,
        vat_id_label: form_info.vat_id_label,
        data: form_info.data
      },
      supplier_info: {
        heading: supplier_info.heading,
        attributes: supplier_info.attributes
      },
      seller_info: {
        heading: seller_info.heading,
        attributes: seller_info.attributes
      },
      order_info: {
        heading: order_info.heading,
        pdf_attributes: order_info.pdf_attributes,
        form_attributes: order_info.form_attributes,
        invoice_date_attribute: order_info.invoice_date_attribute
      },
      id: chargeable.external_id_for_invoice,
      email: chargeable.orderable.email,
      countries: Compliance::Countries.for_select.to_h,
    }
  end

  def order_info
    @_order_info ||= InvoicePresenter::OrderInfo.new(chargeable, address_fields:, additional_notes:, business_vat_id:)
  end

  def supplier_info
    @_supplier_info ||= InvoicePresenter::SupplierInfo.new(chargeable)
  end

  def seller_info
    @_seller_info ||= InvoicePresenter::SellerInfo.new(chargeable)
  end

  def electronic_invoice_data
    {
      invoice_number: chargeable.external_id_numeric_for_invoice,
      invoice_date: chargeable.orderable.created_at.to_date,
      currency_code: "USD",
      supplier: {
        name: "Gumroad, Inc.",
        address: GumroadAddress::STREET,
        city: GumroadAddress::CITY,
        postal_code: GumroadAddress::ZIP_PLUS_FOUR,
        country_code: GumroadAddress::COUNTRY.alpha2,
        vat_id: determine_supplier_vat_id
      },
      customer: {
        name: customer_name,
        address: address_fields[:street_address].presence || chargeable.street_address,
        city: address_fields[:city].presence || chargeable.city,
        postal_code: address_fields[:zip_code].presence || chargeable.zip_code,
        country_code: customer_country_code,
        vat_id: business_vat_id || chargeable.purchase_sales_tax_info&.business_vat_id
      },
      line_items: line_items_for_electronic_invoice,
      totals: {
        line_extension_amount_cents: total_line_extension_cents,
        tax_amount_cents: total_tax_cents,
        shipping_cents: total_shipping_cents,
        payable_amount_cents: total_payable_cents
      }
    }
  end

  private
    attr_reader :business_vat_id, :chargeable, :address_fields, :additional_notes

    def customer_name
      address_fields[:full_name].presence ||
        chargeable.full_name&.strip.presence ||
        chargeable.purchaser&.name ||
        "Customer"
    end

    def customer_country_code
      country_name = address_fields[:country].presence || chargeable.country_or_ip_country
      Compliance::Countries.find_by_name(country_name)&.alpha2 || "US"
    end

    def determine_supplier_vat_id
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

    def line_items_for_electronic_invoice
      chargeable.successful_purchases.filter_map do |purchase|
        next if purchase.is_free_trial_purchase?

        {
          name: purchase.link.name,
          description: purchase.link.name,
          quantity: purchase.quantity,
          unit_price_cents: purchase.displayed_price_cents / purchase.quantity,
          line_extension_cents: purchase.displayed_price_cents,
          tax_cents: purchase.non_refunded_tax_amount,
          tax_rate: calculate_tax_rate(purchase)
        }
      end
    end

    def calculate_tax_rate(purchase)
      return 0.0 if purchase.non_refunded_tax_amount.zero? || purchase.displayed_price_cents.zero?

      ((purchase.non_refunded_tax_amount.to_f / purchase.displayed_price_cents) * 100).round(2)
    end

    def total_line_extension_cents
      chargeable.successful_purchases.sum do |purchase|
        purchase.is_free_trial_purchase? ? 0 : purchase.displayed_price_cents
      end
    end

    def total_tax_cents
      chargeable.successful_purchases.sum do |purchase|
        purchase.is_free_trial_purchase? ? 0 : purchase.non_refunded_tax_amount
      end
    end

    def total_shipping_cents
      chargeable.successful_purchases.sum do |purchase|
        purchase.is_free_trial_purchase? ? 0 : purchase.shipping_cents
      end
    end

    def total_payable_cents
      total_line_extension_cents + total_tax_cents + total_shipping_cents
    end
end
