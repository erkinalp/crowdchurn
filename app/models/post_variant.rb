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

  scope :control, -> { where(is_control: true) }

  def control?
    is_control
  end
end
