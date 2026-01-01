# frozen_string_literal: true

# Controller for handling Kill Bill payment method setup flows.
# Creates payment methods on Kill Bill accounts for future charges.
# This integrates with KillbillChargeProcessor.setup_future_charges! (line 114)
# which works with payment methods created by this controller.
module Killbill
  class SetupIntentsController < ApplicationController
    before_action :authenticate_user!

    # POST /killbill/setup_intents
    # Creates a Kill Bill account if needed and sets up a payment method
    # Returns payment_method_id and account_id for frontend use
    def create
      account = find_or_create_killbill_account
      payment_method = create_payment_method(account)

      if payment_method.present?
        render json: {
          success: true,
          payment_method_id: payment_method.payment_method_id,
          account_id: account.account_id
        }
      else
        render json: {
          success: false,
          error_message: "Failed to create payment method."
        }, status: :unprocessable_entity
      end
    rescue ChargeProcessorInvalidRequestError, ChargeProcessorUnavailableError => e
      logger.error "Error while creating Kill Bill setup intent: `#{e.message}` for user: #{current_user.id}"
      render json: {
        success: false,
        error_message: "There is a temporary problem, please try again."
      }, status: :service_unavailable
    rescue KillBill::Client::API::BadRequest => e
      logger.error "Kill Bill API error while creating setup intent: `#{e.message}` for user: #{current_user.id}"
      render json: {
        success: false,
        error_message: "Invalid payment method data. Please check your details and try again."
      }, status: :unprocessable_entity
    rescue StandardError => e
      logger.error "Unexpected error while creating Kill Bill setup intent: `#{e.message}` for user: #{current_user.id}"
      render json: {
        success: false,
        error_message: "Sorry, something went wrong."
      }, status: :internal_server_error
    end

    # GET /killbill/setup_intents/:id
    # Retrieves payment method status from Kill Bill
    def show
      payment_method = KillBill::Client::Model::PaymentMethod.find_by_id(
        params[:id],
        true,
        killbill_options
      )

      if payment_method.present?
        render json: {
          success: true,
          payment_method_id: payment_method.payment_method_id,
          account_id: payment_method.account_id,
          is_default: payment_method.is_default,
          plugin_name: payment_method.plugin_name,
          plugin_info: extract_safe_plugin_info(payment_method)
        }
      else
        render json: {
          success: false,
          error_message: "Payment method not found."
        }, status: :not_found
      end
    rescue KillBill::Client::API::NotFound
      render json: {
        success: false,
        error_message: "Payment method not found."
      }, status: :not_found
    rescue StandardError => e
      logger.error "Error retrieving Kill Bill payment method: `#{e.message}` for id: #{params[:id]}"
      render json: {
        success: false,
        error_message: "Failed to retrieve payment method."
      }, status: :internal_server_error
    end

    private
      def find_or_create_killbill_account
        options = killbill_options
        external_key = killbill_account_external_key

        # Try to find existing account by external key
        begin
          account = KillBill::Client::Model::Account.find_by_external_key(external_key, false, false, options)
          return account if account.present?
        rescue KillBill::Client::API::NotFound
          # Account doesn't exist, create it
        end

        # Create new Kill Bill account
        account = KillBill::Client::Model::Account.new
        account.external_key = external_key
        account.name = current_user.display_name || current_user.email
        account.email = current_user.email
        account.currency = Currency::USD.upcase

        account.create(options[:username], options[:reason], options[:comment], options)
      end

      def create_payment_method(account)
        options = killbill_options
        payment_method = KillBill::Client::Model::PaymentMethod.new
        payment_method.account_id = account.account_id
        payment_method.plugin_name = payment_method_plugin_name
        payment_method.plugin_info = build_plugin_info
        payment_method.is_default = params[:is_default] != false

        payment_method.create(true, options[:username], options[:reason], options[:comment], options)
      end

      def build_plugin_info
        properties = []

        # Standard card properties
        if params[:card_number].present?
          properties << { key: "card_number", value: params[:card_number], is_updatable: false }
        end
        if params[:card_expiry_month].present?
          properties << { key: "card_expiry_month", value: params[:card_expiry_month], is_updatable: true }
        end
        if params[:card_expiry_year].present?
          properties << { key: "card_expiry_year", value: params[:card_expiry_year], is_updatable: true }
        end
        if params[:card_cvv].present?
          properties << { key: "card_cvv", value: params[:card_cvv], is_updatable: false }
        end
        if params[:card_holder_name].present?
          properties << { key: "card_holder_name", value: params[:card_holder_name], is_updatable: true }
        end
        if params[:card_type].present?
          properties << { key: "card_type", value: params[:card_type], is_updatable: false }
        end
        if params[:last4].present?
          properties << { key: "last4", value: params[:last4], is_updatable: false }
        end
        if params[:country].present?
          properties << { key: "country", value: params[:country], is_updatable: true }
        end
        if params[:zip_code].present?
          properties << { key: "zip_code", value: params[:zip_code], is_updatable: true }
        end

        # Cryptocurrency payment method properties
        # These are required for refunds to work (see killbill_charge_processor.rb lines 389-436)
        if params[:wallet_address].present?
          properties << { key: "wallet_address", value: params[:wallet_address], is_updatable: false }
          properties << { key: "is_cryptocurrency", value: "true", is_updatable: false }
        end

        if params[:cryptocurrency_type].present?
          properties << { key: "cryptocurrency_type", value: params[:cryptocurrency_type], is_updatable: false }
        end

        { properties: properties }
      end

      def payment_method_plugin_name
        # Use cryptocurrency plugin if wallet address is provided
        if params[:wallet_address].present?
          params[:plugin_name] || "killbill-crypto"
        else
          params[:plugin_name] || "killbill-stripe"
        end
      end

      def killbill_account_external_key
        # Use user's external ID as the Kill Bill account external key
        # This ensures consistent account mapping between systems
        "gumroad_user_#{current_user.id}"
      end

      def killbill_options
        merchant_account = current_user.merchant_account(KillbillChargeProcessor.charge_processor_id)

        {
          username: merchant_account&.killbill_username.presence || ENV.fetch("KILLBILL_USER", nil),
          password: merchant_account&.killbill_password.presence || ENV.fetch("KILLBILL_PASSWORD", nil),
          api_key: merchant_account&.killbill_api_key.presence || ENV.fetch("KILLBILL_API_KEY", nil),
          api_secret: merchant_account&.killbill_api_secret.presence || ENV.fetch("KILLBILL_API_SECRET", nil),
          reason: "CrowdChurn payment method setup",
          comment: "Payment method created via SetupIntentsController"
        }
      end

      def extract_safe_plugin_info(payment_method)
        return nil unless payment_method.plugin_info.present?

        # Extract only safe properties (exclude sensitive data like full card numbers)
        safe_keys = %w[last4 card_type expiry_month expiry_year country is_cryptocurrency wallet_address cryptocurrency_type]
        properties = payment_method.plugin_info["properties"] || []

        properties.select { |prop| safe_keys.include?(prop["key"]) }
      end
  end
end
