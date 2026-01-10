# frozen_string_literal: true

# Substitutes variables in message templates
# Example: "Hey {name}! Thanks for {product}!" => "Hey Sarah! Thanks for Premium Course!"
class MessageRenderingService
  def initialize(template_or_variant, purchase)
    @template = template_or_variant
    @purchase = purchase
    @buyer = @purchase.user
    @product = @purchase.link
  end

  def call
    {
      subject: render_text(@template.subject),
      body: render_text(@template.respond_to?(:message_body) ? @template.message_body : @template.try(:message_body))
    }
  end

  private

  def render_text(text)
    return nil if text.blank?

    rendered = text.dup

    # Substitute each variable
    rendered.gsub!('{name}', buyer_name)
    rendered.gsub!('{full_name}', buyer_full_name)
    rendered.gsub!('{email}', buyer_email)
    rendered.gsub!('{product}', product_name)
    rendered.gsub!('{tier}', tier_name)
    rendered.gsub!('{price}', formatted_price)
    rendered.gsub!('{creator}', creator_name)
    rendered.gsub!('{date}', purchase_date)

    rendered
  end

  def buyer_name
    return 'there' unless @buyer

    name = @buyer.name || @purchase.full_name
    return 'there' unless name

    name.split.first || 'there'
  end

  def buyer_full_name
    @buyer&.name || @purchase.full_name || 'Customer'
  end

  def buyer_email
    @buyer&.email || @purchase.email || ''
  end

  def product_name
    @product.name
  end

  def tier_name
    # Get tier/variant from purchase
    variants = BaseVariantsPurchase.where(purchase: @purchase).includes(:base_variant)
    variant = variants.first&.base_variant
    variant&.name || 'Member'
  end

  def formatted_price
    currency = @purchase.currency_type || 'usd'
    amount = @purchase.price_cents / 100.0

    # Simple formatting
    case currency.downcase
    when 'usd'
      "$#{amount}"
    when 'eur'
      "€#{amount}"
    when 'gbp'
      "£#{amount}"
    else
      "#{amount} #{currency.upcase}"
    end
  end

  def creator_name
    @product.user.name || 'Creator'
  end

  def purchase_date
    @purchase.created_at.strftime("%B %d, %Y")
  end
end
