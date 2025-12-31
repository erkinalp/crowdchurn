# frozen_string_literal: true

class VariantPriceService
  BUYER_VARIANT_COOKIE_NAME = :_gumroad_buyer_variant

  attr_reader :product, :installment, :user, :buyer_cookie

  def initialize(product:, installment: nil, user: nil, buyer_cookie: nil)
    @product = product
    @installment = installment
    @user = user
    @buyer_cookie = buyer_cookie
  end

  # Returns the price override in cents if a variant with price_cents is assigned,
  # otherwise returns nil (use default product price)
  def price_override_cents
    return nil unless installment.present?

    assigned_variant = find_or_assign_variant
    return nil unless assigned_variant.present?
    return nil unless assigned_variant.price_cents.present?

    assigned_variant.price_cents
  end

  # Returns the price override in cents and records exposure for A/B test tracking
  # Use this method when displaying the price to a buyer (e.g., checkout page)
  def price_override_cents_with_exposure!
    return nil unless installment.present?

    assigned_variant = find_or_assign_variant
    return nil unless assigned_variant.present?

    record_exposure!

    return nil unless assigned_variant.price_cents.present?
    assigned_variant.price_cents
  end

  # Returns the assigned variant for this buyer/installment combination
  def assigned_variant
    return nil unless installment.present?

    find_or_assign_variant
  end

  # Returns the variant assignment record (not the variant itself)
  # Useful for tracking exposure and conversion
  def variant_assignment
    return nil unless installment.present?

    find_or_assign_variant
    @variant_assignment
  end

  # Record that the variant was exposed (shown) to the buyer
  # Only sets exposed_at if not already set (first exposure)
  def record_exposure!
    return unless installment.present?

    find_or_assign_variant
    @variant_assignment&.record_exposure!
  end

  class << self
    def generate_buyer_cookie
      SecureRandom.uuid
    end

    def get_or_create_buyer_cookie(cookies)
      existing = cookies.signed[BUYER_VARIANT_COOKIE_NAME]
      return existing if existing.present?

      new_cookie = generate_buyer_cookie
      cookies.signed[BUYER_VARIANT_COOKIE_NAME] = {
        value: new_cookie,
        expires: 1.year.from_now,
        httponly: true
      }
      new_cookie
    end
  end

  private
    def find_or_assign_variant
      return @assigned_variant if defined?(@assigned_variant)

      @assigned_variant = VariantAssignment.find_or_assign_for_buyer(
        installment: installment,
        user: user,
        buyer_cookie: buyer_cookie
      )

      # Also store the assignment record for tracking purposes
      if @assigned_variant.present?
        @variant_assignment = VariantAssignment.find_assignment_for_buyer(
          installment: installment,
          user: user,
          buyer_cookie: buyer_cookie
        )
      end

      @assigned_variant
    end
end
