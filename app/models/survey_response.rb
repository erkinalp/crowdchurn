# frozen_string_literal: true

class SurveyResponse < ApplicationRecord
  include ExternalId

  belongs_to :survey
  belongs_to :user, optional: true
  belongs_to :purchase, optional: true
  belongs_to :subscription, optional: true

  has_many :survey_answers, dependent: :destroy

  validates :started_at, presence: true
  validate :must_have_identity
  validate :survey_allows_response, on: :create

  before_validation :set_started_at, on: :create
  after_create :increment_survey_response_count
  after_update :update_survey_completion_rate, if: :saved_change_to_completed_at?

  scope :completed, -> { where.not(completed_at: nil) }
  scope :in_progress, -> { where(completed_at: nil) }
  scope :by_user, ->(user) { where(user: user) }
  scope :by_cookie, ->(cookie) { where(respondent_cookie: cookie) }

  # Privacy: Users can only see their own responses
  def visible_to?(user)
    return false unless user

    # User can see their own response
    return true if self.user_id == user.id

    # Creator can see all responses (aggregated only)
    survey.creator?(user)
  end

  def complete!
    return false if completed_at.present?
    return false unless all_required_questions_answered?

    update!(completed_at: Time.current)
  end

  def completed?
    completed_at.present?
  end

  def in_progress?
    !completed?
  end

  def duration
    return nil unless completed?
    completed_at - started_at
  end

  private

  def must_have_identity
    identities = [user_id, purchase_id, subscription_id, respondent_cookie].compact
    if identities.empty?
      errors.add(:base, "Must have user, purchase, subscription, or respondent_cookie")
    end
  end

  def survey_allows_response
    return if survey.nil?

    unless survey.active?
      errors.add(:base, "Survey is not currently accepting responses")
      return
    end

    # Check if already responded (unless multiple responses allowed)
    unless survey.allow_multiple_responses
      existing = survey.survey_responses
        .where.not(id: id)
        .where.not(completed_at: nil)

      if user_id.present?
        existing = existing.where(user_id: user_id)
      else
        existing = existing.where(respondent_cookie: respondent_cookie)
      end

      if existing.exists?
        errors.add(:base, "You have already completed this survey")
      end
    end
  end

  def set_started_at
    self.started_at ||= Time.current
  end

  def increment_survey_response_count
    survey.increment!(:response_count)
  end

  def update_survey_completion_rate
    # Trigger recalculation if needed
    survey.touch
  end

  def all_required_questions_answered?
    required_question_ids = survey.survey_questions.required_questions.pluck(:id)
    answered_question_ids = survey_answers.pluck(:survey_question_id)

    (required_question_ids - answered_question_ids).empty?
  end
end
