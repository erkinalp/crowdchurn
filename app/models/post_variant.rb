# frozen_string_literal: true

class PostVariant < ApplicationRecord
  include ExternalId

  belongs_to :installment
  has_many :variant_distribution_rules, dependent: :destroy
  has_many :variant_assignments, dependent: :destroy
  has_many :base_variants, through: :variant_distribution_rules
  has_many :comments, dependent: :nullify

  validates :name, presence: true
  validates :message, presence: true
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :control, -> { where(is_control: true) }

  def control?
    is_control
  end
end
