# frozen_string_literal: true

class Survey < ApplicationRecord
  include ExternalId

  belongs_to :surveyable, polymorphic: true
  belongs_to :base_variant, optional: true

  has_many :survey_questions, -> { order(:position) }, dependent: :destroy, inverse_of: :survey
  has_many :survey_responses, dependent: :destroy

  accepts_nested_attributes_for :survey_questions, allow_destroy: true, reject_if: :all_blank

  validates :title, presence: true, length: { maximum: 255 }
  validates :surveyable, presence: true

  scope :alive, -> { where(deleted_at: nil) }
  scope :active, -> { alive.where('closes_at IS NULL OR closes_at > ?', Time.current) }
  scope :closed, -> { alive.where('closes_at <= ?', Time.current) }
  scope :for_variant, ->(variant_id) { where(base_variant_id: variant_id) }
  scope :for_variants, ->(variant_ids) { where(base_variant_id: variant_ids) }

  # Performance scopes for crowdsourcing
  scope :available_for_user, ->(user) do
    completed_survey_ids = SurveyResponse.where(user: user).where.not(completed_at: nil).pluck(:survey_id)
    active.where.not(id: completed_survey_ids)
  end

  scope :with_response_stats, -> do
    select('surveys.*, COUNT(DISTINCT survey_responses.id) as responses_count')
      .left_joins(:survey_responses)
      .group('surveys.id')
  end

  def active?
    deleted_at.nil? && (closes_at.nil? || closes_at > Time.current)
  end

  def completion_rate
    return 0 if response_count.zero?
    completed_count = survey_responses.where.not(completed_at: nil).count
    (completed_count.to_f / response_count * 100).round(2)
  end

  def completed_responses
    survey_responses.where.not(completed_at: nil)
  end

  # Privacy: Only creator can see all responses
  def responses_visible_to(user)
    return survey_responses.none unless user

    # Creator can see all responses
    if creator?(user)
      survey_responses
    else
      # Users can only see their own responses
      survey_responses.where(user: user)
    end
  end

  def creator?(user)
    case surveyable_type
    when 'Link'
      surveyable.user_id == user.id
    when 'Installment'
      surveyable.seller_id == user.id || surveyable.link&.user_id == user.id
    else
      false
    end
  end

  def creator
    case surveyable_type
    when 'Link'
      surveyable.user
    when 'Installment'
      surveyable.seller || surveyable.link&.user
    end
  end

  # Check if user has already responded
  def responded_by?(user: nil, cookie: nil)
    return false if user.nil? && cookie.nil?

    query = survey_responses
    query = if user.present?
      query.where(user: user)
    else
      query.where(respondent_cookie: cookie)
    end

    query.where.not(completed_at: nil).exists?
  end

  # Check if user can respond
  def can_respond?(user: nil, cookie: nil)
    return false unless active?
    return true if allow_multiple_responses
    !responded_by?(user: user, cookie: cookie)
  end
end
