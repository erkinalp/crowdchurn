# frozen_string_literal: true

class KillbillCatalogManager
  include KillbillErrorHandler
  include CurrencyHelper

  PRODUCT_CATEGORY_BASE = "BASE"
  PRODUCT_CATEGORY_ADD_ON = "ADD_ON"
  PRODUCT_CATEGORY_STANDALONE = "STANDALONE"

  BILLING_PERIOD_MONTHLY = "MONTHLY"
  BILLING_PERIOD_ANNUAL = "ANNUAL"
  BILLING_PERIOD_WEEKLY = "WEEKLY"
  BILLING_PERIOD_QUARTERLY = "QUARTERLY"
  BILLING_PERIOD_NO_BILLING_PERIOD = "NO_BILLING_PERIOD"

  PHASE_TYPE_TRIAL = "TRIAL"
  PHASE_TYPE_DISCOUNT = "DISCOUNT"
  PHASE_TYPE_FIXEDTERM = "FIXEDTERM"
  PHASE_TYPE_EVERGREEN = "EVERGREEN"

  # Supported currencies for multi-currency catalogs (Kill Bill supports these)
  SUPPORTED_CATALOG_CURRENCIES = %w[USD EUR GBP JPY AUD CAD CHF].freeze

  def initialize(merchant_account)
    @merchant_account = merchant_account
    configure_client
  end

  def upload_catalog(catalog_xml)
    with_killbill_error_handler do
      KillBill::Client::Model::Catalog.upload_tenant_catalog(
        catalog_xml,
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        killbill_options
      )
    end
  end

  def get_catalog(requested_date: nil)
    with_killbill_error_handler do
      KillBill::Client::Model::Catalog.get_tenant_catalog(
        requested_date,
        killbill_options
      )
    end
  end

  def get_available_plans
    with_killbill_error_handler do
      catalog = get_catalog
      return [] unless catalog.present?

      extract_plans_from_catalog(catalog)
    end
  end

  def generate_catalog_for_product(product)
    products = [build_product_definition(product)]
    currencies = currencies_for_product(product)
    plans = build_plans_for_product(product, currencies)
    price_lists = [{ name: "DEFAULT", plans: plans.map { |p| p[:name] } }]

    build_catalog_xml(
      name: "crowdchurn-catalog",
      effective_date: Time.current.iso8601,
      currencies: currencies,
      products: products,
      plans: plans,
      price_lists: price_lists
    )
  end

  def sync_product_to_catalog(product)
    catalog_xml = generate_catalog_for_product(product)
    upload_catalog(catalog_xml)
  end

  private
    def configure_client
      instance_url = @merchant_account&.killbill_instance_url.presence ||
                     ENV.fetch("KILLBILL_URL", nil)

      unless instance_url.present?
        raise ChargeProcessorInvalidRequestError.new(
          "Kill Bill instance URL not configured"
        )
      end

      KillBill::Client.url = instance_url
    end

    def killbill_options
      @killbill_options ||= {
        username: @merchant_account&.killbill_username.presence ||
                  ENV.fetch("KILLBILL_USER", nil),
        password: @merchant_account&.killbill_password.presence ||
                  ENV.fetch("KILLBILL_PASSWORD", nil),
        api_key: @merchant_account&.killbill_api_key.presence ||
                 ENV.fetch("KILLBILL_API_KEY", nil),
        api_secret: @merchant_account&.killbill_api_secret.presence ||
                    ENV.fetch("KILLBILL_API_SECRET", nil),
        reason: "CrowdChurn catalog management",
        comment: "Automated via CrowdChurn"
      }
    end

    def build_product_definition(product)
      {
        name: product_name_for_killbill(product),
        category: PRODUCT_CATEGORY_BASE,
        included: [],
        available: []
      }
    end

    def build_plans_for_product(product, currencies)
      plans = []

      product.prices.is_buy.alive.each do |price|
        next unless price.recurrence.present?

        plan = {
          name: plan_name_for_price(product, price),
          product: product_name_for_killbill(product),
          billing_period: recurrence_to_billing_period(price.recurrence),
          phases: build_phases_for_price(product, price, currencies)
        }

        plans << plan
      end

      plans
    end

    def build_phases_for_price(product, price, currencies)
      phases = []

      if product.free_trial_duration_in_days.present? && product.free_trial_duration_in_days > 0
        # For trial phase, all currencies have zero price
        trial_prices = currencies.map { |currency| { currency: currency, value: 0 } }
        phases << {
          type: PHASE_TYPE_TRIAL,
          duration: {
            unit: "DAYS",
            number: product.free_trial_duration_in_days
          },
          fixed_prices: trial_prices
        }
      end

      # Build recurring prices for all supported currencies based on pricing_mode
      recurring_prices = build_recurring_prices_for_currencies(product, price, currencies)

      phases << {
        type: PHASE_TYPE_EVERGREEN,
        duration: {
          unit: "UNLIMITED",
          number: -1
        },
        recurring_prices: recurring_prices
      }

      phases
    end

    def product_name_for_killbill(product)
      product.name.parameterize.underscore.gsub(/[^a-z0-9_]/, "_")
    end

    def plan_name_for_price(product, price)
      product_name = product_name_for_killbill(product)
      billing_period = recurrence_to_billing_period(price.recurrence).downcase
      "#{product_name}-#{billing_period}"
    end

    def recurrence_to_billing_period(recurrence)
      case recurrence
      when BasePrice::Recurrence::MONTHLY
        BILLING_PERIOD_MONTHLY
      when BasePrice::Recurrence::YEARLY
        BILLING_PERIOD_ANNUAL
      when BasePrice::Recurrence::QUARTERLY
        BILLING_PERIOD_QUARTERLY
      when BasePrice::Recurrence::WEEKLY
        BILLING_PERIOD_WEEKLY
      else
        BILLING_PERIOD_MONTHLY
      end
    end

    def extract_plans_from_catalog(catalog)
      return [] unless catalog.is_a?(Array) && catalog.first.present?

      catalog_version = catalog.first
      return [] unless catalog_version["plans"].present?

      catalog_version["plans"].map do |plan|
        {
          name: plan["name"],
          product: plan["product"],
          billing_period: plan["billingPeriod"],
          phases: plan["phases"]
        }
      end
    end

    def currencies_for_product(product)
      case product.pricing_mode&.to_sym
      when :gross
        # For gross mode, include all supported currencies for FX conversion
        SUPPORTED_CATALOG_CURRENCIES
      when :multi_currency
        # For multi_currency mode, include currencies that have explicit prices
        explicit_currencies = product.prices.is_buy.alive.pluck(:currency).uniq.map(&:upcase)
        # Always include the product's default currency
        default_currency = product.price_currency_type.to_s.upcase
        ([default_currency] + explicit_currencies).uniq & SUPPORTED_CATALOG_CURRENCIES
      else
        # For legacy mode, only include the product's default currency
        [product.price_currency_type.to_s.upcase]
      end
    end

    def build_recurring_prices_for_currencies(product, price, currencies)
      product_currency = product.price_currency_type.to_s.downcase
      base_price_cents = price.price_cents

      currencies.map do |currency|
        currency_lower = currency.downcase
        price_value = resolve_price_for_currency(product, price, currency_lower, product_currency, base_price_cents)

        { currency: currency, value: price_value }
      end
    end

    def resolve_price_for_currency(product, price, target_currency, product_currency, base_price_cents)
      case product.pricing_mode&.to_sym
      when :gross
        # For gross mode, convert using FX rates
        if target_currency == product_currency
          price_cents_to_decimal(base_price_cents, product_currency)
        else
          converted_cents = convert_price_with_fx(base_price_cents, product_currency, target_currency)
          price_cents_to_decimal(converted_cents, target_currency)
        end
      when :multi_currency
        # For multi_currency mode, look up explicit price or fall back to base
        explicit_price = product.price_for_currency(target_currency, recurrence: price.recurrence)
        if explicit_price.present?
          price_cents_to_decimal(explicit_price.price_cents, target_currency)
        else
          price_cents_to_decimal(base_price_cents, product_currency)
        end
      else
        # For legacy mode, use the base price
        price_cents_to_decimal(base_price_cents, product_currency)
      end
    end

    def convert_price_with_fx(price_cents, source_currency, target_currency)
      # Convert source currency to base currency (USD), then to target currency
      base_units = get_base_currency_units(source_currency, price_cents)
      base_currency_to_display_currency(target_currency, base_units)
    end

    def price_cents_to_decimal(price_cents, currency)
      # Convert cents to decimal value for Kill Bill catalog
      # Handle single-unit currencies like JPY
      if is_currency_type_single_unit?(currency)
        price_cents.to_f
      else
        price_cents / 100.0
      end
    end

    def build_catalog_xml(name:, effective_date:, currencies:, products:, plans:, price_lists:)
      xml = Builder::XmlMarkup.new(indent: 2)
      xml.instruct! :xml, version: "1.0", encoding: "UTF-8"

      xml.catalog(xmlns: "http://docs.killbill.io/catalog/v1") do
        xml.effectiveDate effective_date
        xml.catalogName name

        xml.currencies do
          currencies.each { |currency| xml.currency currency }
        end

        xml.products do
          products.each do |product|
            xml.product(name: product[:name]) do
              xml.category product[:category]
            end
          end
        end

        xml.rules do
          xml.changePolicy do
            xml.changePolicyCase do
              xml.policy "IMMEDIATE"
            end
          end
          xml.cancelPolicy do
            xml.cancelPolicyCase do
              xml.policy "IMMEDIATE"
            end
          end
        end

        xml.plans do
          plans.each do |plan|
            xml.plan(name: plan[:name]) do
              xml.product plan[:product]

              # Add trial phase if present
              trial_phase = plan[:phases].find { |p| p[:type] == PHASE_TYPE_TRIAL }
              if trial_phase
                xml.initialPhases do
                  xml.phase(type: "TRIAL") do
                    xml.duration do
                      xml.unit trial_phase[:duration][:unit]
                      xml.number trial_phase[:duration][:number]
                    end
                    xml.fixed do
                      xml.fixedPrice do
                        trial_phase[:fixed_prices].each do |price_entry|
                          xml.price do
                            xml.currency price_entry[:currency]
                            xml.value price_entry[:value]
                          end
                        end
                      end
                    end
                  end
                end
              end

              xml.finalPhase(type: "EVERGREEN") do
                xml.duration do
                  xml.unit "UNLIMITED"
                  xml.number(-1)
                end
                xml.billingPeriod plan[:billing_period]
                xml.recurring do
                  xml.recurringPrice do
                    plan[:phases].select { |p| p[:type] == PHASE_TYPE_EVERGREEN }.each do |phase|
                      phase[:recurring_prices].each do |price_entry|
                        xml.price do
                          xml.currency price_entry[:currency]
                          xml.value price_entry[:value]
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end

        xml.priceLists do
          price_lists.each do |price_list|
            xml.defaultPriceList(name: price_list[:name]) do
              price_list[:plans].each { |plan_name| xml.plan plan_name }
            end
          end
        end
      end

      xml.target!
    end
end
