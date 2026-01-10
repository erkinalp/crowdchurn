# frozen_string_literal: true

# Handles trigger evaluation and automated message sending
class MessageTriggerService
  def self.process_purchase(purchase)
    new(purchase).process_immediate_triggers
  end

  def initialize(purchase)
    @purchase = purchase
    @product = purchase.link
  end

  def process_immediate_triggers
    templates = MessageTemplate
                  .active
                  .where(templateable: @product)
                  .for_trigger(:immediate_purchase)
                  .by_priority

    templates.each do |template|
      send_message(template)
    end
  end

  def process_delayed_triggers
    # Called by background job for delayed messages
    templates = MessageTemplate
                  .active
                  .where(templateable: @product)
                  .for_trigger(:delayed_purchase)
                  .by_priority

    templates.each do |template|
      next unless should_send_delayed?(template)
      send_message(template)
    end
  end

  def process_survey_completion_trigger(survey_response)
    # Trigger when survey is completed
    survey = survey_response.survey

    templates = MessageTemplate
                  .active
                  .where(templateable: survey.surveyable)
                  .for_trigger(:survey_completion)
                  .by_priority

    templates.each do |template|
      send_message(template)
    end
  end

  private

  def send_message(template)
    # Prevent duplicates
    return if AutomatedMessage.exists?(
      purchase: @purchase,
      message_template: template
    )

    # Return if buyer has no user account (can't receive messages)
    return unless @purchase.user.present?

    # Select variant (if A/B testing enabled)
    variant = template.select_variant

    # Render message with variable substitution
    rendered = MessageRenderingService.new(variant || template, @purchase).call

    # Create automated message
    AutomatedMessage.create!(
      message_template: template,
      purchase: @purchase,
      user: @purchase.user,
      sender: @product.user,
      message_template_variant: variant.is_a?(MessageTemplateVariant) ? variant : nil,
      rendered_subject: rendered[:subject],
      rendered_message: rendered[:body],
      sent_at: Time.current
    )
  rescue => e
    # Log error but don't fail the purchase
    Rails.logger.error("Failed to send automated message: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end

  def should_send_delayed?(template)
    delay_hours = template.trigger_config&.dig('delay_hours')
    return false unless delay_hours

    time_since_purchase = (Time.current - @purchase.created_at) / 1.hour
    time_since_purchase >= delay_hours.to_f
  end
end
