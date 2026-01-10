# frozen_string_literal: true

class AddPerformanceIndexesForCrowdsourcing < ActiveRecord::Migration[7.1]
  def change
    # Performance indexes for high-volume crowdsourcing scenarios

    # Fast lookup of available surveys for a specific variant
    add_index :surveys, [:base_variant_id, :deleted_at, :closes_at],
              name: "index_surveys_on_variant_availability"

    # Fast lookup of user's incomplete responses (for task assignment)
    add_index :survey_responses, [:user_id, :completed_at],
              name: "index_survey_responses_on_user_completion",
              where: "completed_at IS NULL"

    # Fast lookup of responses needing completion by survey
    add_index :survey_responses, [:survey_id, :started_at, :completed_at],
              name: "index_survey_responses_on_survey_progress"

    # Fast aggregation queries for analytics
    add_index :survey_answers, [:survey_question_id, :created_at],
              name: "index_survey_answers_on_question_and_date"

    # Fast lookup for preventing duplicate responses
    add_index :survey_responses, [:survey_id, :user_id, :completed_at],
              name: "index_survey_responses_uniqueness_check",
              where: "user_id IS NOT NULL"

    # Fast lookup for batch task assignment
    add_index :surveys, [:surveyable_type, :surveyable_id, :base_variant_id, :deleted_at],
              name: "index_surveys_on_polymorphic_variant"

    # Optimize option response counting
    add_index :survey_answers, [:survey_question_option_id],
              name: "index_survey_answers_on_option_id",
              where: "survey_question_option_id IS NOT NULL"
  end
end
