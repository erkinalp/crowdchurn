# frozen_string_literal: true

class SurveyQuestion < ApplicationRecord
  include ExternalId

  belongs_to :survey, inverse_of: :survey_questions
  has_many :survey_question_options, -> { order(:position) }, dependent: :destroy
  has_many :survey_answers, dependent: :destroy

  accepts_nested_attributes_for :survey_question_options, allow_destroy: true, reject_if: :all_blank

  enum :question_type, {
    text_short: 0,
    text_long: 1,
    multiple_choice_single: 2,
    multiple_choice_multi: 3,
    rating_scale: 4,
    yes_no: 5
  }, prefix: true

  validates :question_text, presence: true, length: { maximum: 1000 }
  validates :question_type, presence: true
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :validate_options_for_type

  scope :alive, -> { where(deleted_at: nil) }
  scope :required_questions, -> { where(required: true) }

  acts_as_list scope: :survey, column: :position

  # Question type helpers
  def needs_options?
    multiple_choice_single? || multiple_choice_multi? || yes_no?
  end

  def allows_text_answer?
    text_short? || text_long?
  end

  def allows_rating?
    rating_scale?
  end

  def allows_multiple_selections?
    multiple_choice_multi?
  end

  # Get aggregated stats for this question (only for creator)
  def answer_stats
    case question_type
    when 'multiple_choice_single', 'multiple_choice_multi', 'yes_no'
      option_breakdown
    when 'rating_scale'
      rating_stats
    when 'text_short', 'text_long'
      { total_responses: survey_answers.where.not(text_answer: nil).count }
    end
  end

  private

  def option_breakdown
    survey_question_options.includes(:survey_answers).map do |option|
      {
        option_id: option.id,
        option_text: option.option_text,
        count: option.survey_answers.count,
        percentage: total_responses.zero? ? 0 : (option.survey_answers.count.to_f / total_responses * 100).round(2)
      }
    end
  end

  def rating_stats
    ratings = survey_answers.where.not(rating_value: nil).pluck(:rating_value)
    return { count: 0 } if ratings.empty?

    {
      count: ratings.size,
      average: (ratings.sum.to_f / ratings.size).round(2),
      min: ratings.min,
      max: ratings.max,
      distribution: ratings.group_by(&:itself).transform_values(&:count)
    }
  end

  def total_responses
    @total_responses ||= survey.completed_responses.count
  end

  def validate_options_for_type
    if needs_options? && survey_question_options.reject(&:marked_for_destruction?).empty?
      errors.add(:base, "#{question_type.humanize} questions must have at least one option")
    end

    if yes_no? && survey_question_options.reject(&:marked_for_destruction?).size != 2
      errors.add(:base, "Yes/No questions must have exactly 2 options")
    end
  end
end
