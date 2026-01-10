# frozen_string_literal: true

class CreateSurveysTables < ActiveRecord::Migration[7.1]
  def change
    # Create surveys table - surveys can be attached to products/posts or their variants
    create_table :surveys do |t|
      t.references :surveyable, polymorphic: true, null: false, index: true
      t.references :base_variant, null: true, foreign_key: true, index: true
      t.string :title, null: false
      t.text :description
      t.boolean :anonymous, default: false, null: false
      t.boolean :allow_multiple_responses, default: false, null: false
      t.datetime :closes_at
      t.integer :response_count, default: 0, null: false

      t.timestamps
      t.datetime :deleted_at
    end

    add_index :surveys, [:surveyable_type, :surveyable_id, :deleted_at],
              name: "index_surveys_on_surveyable_and_deleted_at"
    add_index :surveys, :deleted_at

    # Create survey_questions table
    create_table :survey_questions do |t|
      t.references :survey, null: false, foreign_key: true, index: true
      t.string :question_text, null: false
      t.integer :question_type, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.boolean :required, default: false, null: false
      t.json :settings # for type-specific settings (min/max, character limits, etc.)

      t.timestamps
      t.datetime :deleted_at
    end

    add_index :survey_questions, [:survey_id, :position],
              name: "index_survey_questions_on_survey_and_position"
    add_index :survey_questions, :deleted_at

    # Create survey_question_options table (for multiple choice questions)
    create_table :survey_question_options do |t|
      t.references :survey_question, null: false, foreign_key: true, index: true
      t.string :option_text, null: false
      t.integer :position, null: false, default: 0
      t.integer :response_count, default: 0, null: false

      t.timestamps
    end

    add_index :survey_question_options, [:survey_question_id, :position],
              name: "index_survey_question_options_on_question_and_position"

    # Create survey_responses table - tracks individual user responses
    # PRIVACY: Each user can only see their own responses
    create_table :survey_responses do |t|
      t.references :survey, null: false, foreign_key: true, index: true
      t.references :user, null: true, foreign_key: true, index: true
      t.references :purchase, null: true, foreign_key: true, index: true
      t.references :subscription, null: true, foreign_key: true, index: true
      t.string :respondent_cookie # for anonymous tracking
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :survey_responses, [:survey_id, :user_id],
              name: "index_survey_responses_on_survey_and_user",
              unique: true,
              where: "user_id IS NOT NULL AND allow_multiple_responses = FALSE"
    add_index :survey_responses, [:survey_id, :respondent_cookie],
              name: "index_survey_responses_on_survey_and_cookie",
              where: "respondent_cookie IS NOT NULL"
    add_index :survey_responses, [:survey_id, :completed_at],
              name: "index_survey_responses_on_survey_and_completed"

    # Create survey_answers table - stores individual answers to questions
    # PRIVACY: Answers are private and only shown to the survey creator in aggregate
    create_table :survey_answers do |t|
      t.references :survey_response, null: false, foreign_key: true, index: true
      t.references :survey_question, null: false, foreign_key: true, index: true
      t.references :survey_question_option, null: true, foreign_key: true, index: true
      t.text :text_answer
      t.integer :rating_value

      t.timestamps
    end

    add_index :survey_answers, [:survey_response_id, :survey_question_id],
              name: "index_survey_answers_on_response_and_question",
              unique: true
  end
end
