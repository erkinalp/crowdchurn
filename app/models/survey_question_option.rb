# frozen_string_literal: true

class SurveyQuestionOption < ApplicationRecord
  belongs_to :survey_question
  has_many :survey_answers, dependent: :nullify

  validates :option_text, presence: true, length: { maximum: 500 }
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }

  acts_as_list scope: :survey_question, column: :position

  after_save :update_response_count

  private

  def update_response_count
    update_column(:response_count, survey_answers.count)
  end
end
