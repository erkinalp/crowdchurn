# frozen_string_literal: true

class SurveyAnswer < ApplicationRecord
  belongs_to :survey_response
  belongs_to :survey_question
  belongs_to :survey_question_option, optional: true

  validates :survey_response, presence: true
  validates :survey_question, presence: true
  validate :answer_matches_question_type
  validate :answer_is_present

  # Privacy: Answers are only visible to the respondent and the survey creator
  def visible_to?(user)
    return false unless user

    # User can see their own answer
    return true if survey_response.user_id == user.id

    # Creator can see answers (but typically only in aggregate)
    survey_response.survey.creator?(user)
  end

  private

  def answer_matches_question_type
    case survey_question&.question_type
    when 'text_short', 'text_long'
      unless text_answer.present?
        errors.add(:text_answer, "must be provided for text questions")
      end
    when 'multiple_choice_single', 'multiple_choice_multi', 'yes_no'
      unless survey_question_option_id.present?
        errors.add(:survey_question_option, "must be selected")
      end

      # Verify option belongs to the question
      if survey_question_option && survey_question_option.survey_question_id != survey_question_id
        errors.add(:survey_question_option, "does not belong to this question")
      end
    when 'rating_scale'
      unless rating_value.present?
        errors.add(:rating_value, "must be provided for rating questions")
      end

      # Validate rating is within range (if settings specify)
      if survey_question.settings&.dig('min_rating') && survey_question.settings&.dig('max_rating')
        min = survey_question.settings['min_rating']
        max = survey_question.settings['max_rating']
        unless rating_value.between?(min, max)
          errors.add(:rating_value, "must be between #{min} and #{max}")
        end
      end
    end
  end

  def answer_is_present
    has_answer = text_answer.present? || survey_question_option_id.present? || rating_value.present?
    unless has_answer
      errors.add(:base, "An answer must be provided")
    end
  end
end
