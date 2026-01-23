# frozen_string_literal: true

class KillbillCatalogManager
  include KillbillErrorHandler

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
    plans = build_plans_for_product(product)
    price_lists = [{ name: "DEFAULT", plans: plans.map { |p| p[:name] } }]

    build_catalog_xml(
      name: "crowdchurn-catalog",
      effective_date: Time.current.iso8601,
      currencies: [Currency::USD.upcase],
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

    def build_plans_for_product(product)
      plans = []

      product.prices.is_buy.alive.each do |price|
        next unless price.recurrence.present?

        plan = {
          name: plan_name_for_price(product, price),
          product: product_name_for_killbill(product),
          billing_period: recurrence_to_billing_period(price.recurrence),
          phases: build_phases_for_price(product, price)
        }

        plans << plan
      end

      plans
    end

    def build_phases_for_price(product, price)
      phases = []

      if product.free_trial_duration_in_days.present? && product.free_trial_duration_in_days > 0
        phases << {
          type: PHASE_TYPE_TRIAL,
          duration: {
            unit: "DAYS",
            number: product.free_trial_duration_in_days
          },
          fixed_price: { currency: Currency::USD.upcase, value: 0 }
        }
      end

      phases << {
        type: PHASE_TYPE_EVERGREEN,
        duration: {
          unit: "UNLIMITED",
          number: -1
        },
        recurring_price: {
          currency: Currency::USD.upcase,
          value: price.price_cents / 100.0
        }
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
              xml.finalPhase(type: "EVERGREEN") do
                xml.duration do
                  xml.unit "UNLIMITED"
                  xml.number(-1)
                end
                xml.billingPeriod plan[:billing_period]
                xml.recurringPrice do
                  plan[:phases].select { |p| p[:type] == PHASE_TYPE_EVERGREEN }.each do |phase|
                    xml.price do
                      xml.currency phase[:recurring_price][:currency]
                      xml.value phase[:recurring_price][:value]
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
