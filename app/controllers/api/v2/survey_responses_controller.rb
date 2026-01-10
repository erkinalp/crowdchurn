# frozen_string_literal: true

module Api
  module V2
    class SurveyResponsesController < ApiController
      before_action :set_survey

      # POST /api/v2/surveys/:survey_id/responses
      # Create and submit a survey response
      def create
        # Can be authenticated user or anonymous with API key
        @response = @survey.survey_responses.build
        @response.user = current_api_user if api_user_signed_in?
        @response.respondent_cookie = params[:respondent_id] if params[:respondent_id]

        # Save answers from request
        if @response.save && save_answers(@response, params[:answers])
          # Try to mark as complete if all required answered
          @response.complete! if params[:complete]

          render json: {
            response: response_json(@response),
            message: @response.completed? ? 'Survey completed' : 'Response saved'
          }, status: :created
        else
          render json: { errors: @response.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v2/surveys/:survey_id/responses/:id
      def show
        @response = @survey.survey_responses.find_by!(external_id: params[:id])

        # Privacy: only allow viewing own response or if survey creator
        unless can_view_response?(@response)
          render json: { error: 'Unauthorized' }, status: :forbidden
          return
        end

        render json: { response: response_json(@response, include_answers: true) }
      end

      # PATCH /api/v2/surveys/:survey_id/responses/:id
      def update
        @response = @survey.survey_responses.find_by!(external_id: params[:id])

        unless can_view_response?(@response)
          render json: { error: 'Unauthorized' }, status: :forbidden
          return
        end

        if save_answers(@response, params[:answers])
          @response.complete! if params[:complete]

          render json: {
            response: response_json(@response, include_answers: true),
            message: @response.completed? ? 'Survey completed' : 'Response updated'
          }
        else
          render json: { errors: ['Failed to save answers'] }, status: :unprocessable_entity
        end
      end

      private

      def set_survey
        @survey = Survey.alive.find_by!(external_id: params[:survey_id])
      end

      def can_view_response?(response)
        return true if response.user == current_api_user
        return true if @survey.creator?(current_api_user)
        false
      end

      def save_answers(response, answers_data)
        return false unless answers_data.is_a?(Array)

        answers_data.each do |answer_data|
          question = @survey.survey_questions.find_by(external_id: answer_data[:question_id])
          next unless question

          answer = response.survey_answers.find_or_initialize_by(survey_question: question)

          case question.question_type
          when 'text_short', 'text_long'
            answer.text_answer = answer_data[:text_answer]
          when 'multiple_choice_single', 'yes_no'
            option = question.survey_question_options.find_by(external_id: answer_data[:option_id])
            answer.survey_question_option = option
          when 'rating_scale'
            answer.rating_value = answer_data[:rating_value]
          end

          answer.save!
        end

        true
      rescue => e
        Rails.logger.error("Error saving survey answers: #{e.message}")
        false
      end

      def response_json(response, include_answers: false)
        data = {
          id: response.external_id,
          survey_id: @survey.external_id,
          started_at: response.started_at,
          completed_at: response.completed_at,
          completed: response.completed?
        }

        if include_answers
          data[:answers] = response.survey_answers.map do |answer|
            {
              question_id: answer.survey_question.external_id,
              question_text: answer.survey_question.question_text,
              question_type: answer.survey_question.question_type,
              text_answer: answer.text_answer,
              option_id: answer.survey_question_option&.external_id,
              option_text: answer.survey_question_option&.option_text,
              rating_value: answer.rating_value
            }
          end
        end

        data
      end
    end
  end
end
