# frozen_string_literal: true

class MessageTemplate < ApplicationRecord
  include ExternalId

  belongs_to :user # Creator
  belongs_to :templateable, polymorphic: true
  has_many :message_template_variants, dependent: :destroy
  has_many :automated_messages, dependent: :restrict_with_error

  accepts_nested_attributes_for :message_template_variants, allow_destroy: true, reject_if: :all_blank

  enum :trigger_type, {
    immediate_purchase: 0,
    delayed_purchase: 1,
    first_access: 2,
    survey_completion: 3,
    milestone: 4,
    tier_upgrade: 5,
    abandoned_response: 6
  }, prefix: true

  validates :name, presence: true, length: { maximum: 255 }
  validates :message_body, presence: true
  validates :trigger_type, presence: true
  validate :validate_trigger_config
  validate :validate_variables_in_message

  scope :alive, -> { where(deleted_at: nil) }
  scope :active, -> { alive.where(active: true) }
  scope :for_trigger, ->(trigger) { active.where(trigger_type: trigger) }
  scope :for_product, ->(product) { where(templateable: product) }
  scope :by_priority, -> { order(priority: :desc, created_at: :asc) }

  # Available variables for message personalization
  VARIABLES = {
    '{name}' => 'Buyer first name',
    '{full_name}' => 'Buyer full name',
    '{email}' => 'Buyer email',
    '{product}' => 'Product name',
    '{tier}' => 'Membership tier name',
    '{price}' => 'Purchase price',
    '{creator}' => 'Creator name',
    '{date}' => 'Purchase date'
  }.freeze

  def render_for(purchase)
    variant = select_variant
    MessageRenderingService.new(variant || self, purchase).call
  end

  def select_variant
    return nil unless message_template_variants.any?

    # Weighted random selection for A/B testing
    total_weight = message_template_variants.sum(:weight)
    return message_template_variants.first if total_weight.zero?

    random_value = rand(total_weight)

    cumulative = 0
    message_template_variants.each do |variant|
      cumulative += variant.weight
      return variant if random_value < cumulative
    end

    message_template_variants.first
  end

  def analytics
    MessageTemplateAnalyticsService.new(self).call
  end

  private

  def validate_trigger_config
    case trigger_type
    when 'delayed_purchase', 'milestone'
      unless trigger_config.is_a?(Hash) && trigger_config['delay_hours'].present?
        errors.add(:trigger_config, "must include delay_hours for #{trigger_type}")
      end
    end
  end

  def validate_variables_in_message
    # Warn about invalid variables (not blocking, just helpful)
    invalid_vars = message_body.scan(/\{[^}]+\}/) - VARIABLES.keys
    if invalid_vars.any?
      errors.add(:message_body, "contains unknown variables: #{invalid_vars.join(', ')}")
    end
  end
end
