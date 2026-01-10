# frozen_string_literal: true

module Api
  module V2
    class SurveysController < ApiController
      before_action :authenticate_api_user!
      before_action :set_survey, only: [:show, :update, :destroy, :analytics, :responses]
      before_action :authorize_survey, only: [:update, :destroy, :analytics, :responses]

      # GET /api/v2/surveys
      def index
        @surveys = current_api_user.surveys
                                   .alive
                                   .includes(:survey_questions)
                                   .order(created_at: :desc)
                                   .page(params[:page])

        render json: {
          surveys: @surveys.map { |s| survey_json(s) },
          meta: pagination_meta(@surveys)
        }
      end

      # GET /api/v2/surveys/:id
      def show
        render json: { survey: survey_json(@survey, include_questions: true) }
      end

      # POST /api/v2/surveys
      def create
        surveyable = find_surveyable

        @survey = surveyable.surveys.build(survey_params)

        if @survey.save
          render json: { survey: survey_json(@survey, include_questions: true) }, status: :created
        else
          render json: { errors: @survey.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v2/surveys/:id
      def update
        if @survey.update(survey_params)
          render json: { survey: survey_json(@survey, include_questions: true) }
        else
          render json: { errors: @survey.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v2/surveys/:id
      def destroy
        @survey.update(deleted_at: Time.current)
        head :no_content
      end

      # GET /api/v2/surveys/:id/analytics
      def analytics
        stats = SurveyAnalyticsService.new(@survey).call

        render json: {
          survey_id: @survey.external_id,
          analytics: stats
        }
      end

      # GET /api/v2/surveys/:id/responses
      def responses
        @responses = @survey.survey_responses
                           .includes(:survey_answers, :user)
                           .order(created_at: :desc)
                           .page(params[:page])

        render json: {
          responses: @responses.map { |r| response_json(r) },
          meta: pagination_meta(@responses)
        }
      end

      private

      def set_survey
        @survey = Survey.alive.find_by!(external_id: params[:id])
      end

      def authorize_survey
        unless @survey.creator?(current_api_user)
          render json: { error: 'Unauthorized' }, status: :forbidden
        end
      end

      def find_surveyable
        if params[:link_id]
          current_api_user.links.find_by!(external_id: params[:link_id])
        elsif params[:installment_id]
          current_api_user.installments.find_by!(external_id: params[:installment_id])
        else
          render json: { error: 'Must specify link_id or installment_id' }, status: :bad_request
          nil
        end
      end

      def survey_params
        params.require(:survey).permit(
          :title, :description, :anonymous, :allow_multiple_responses,
          :closes_at, :base_variant_id,
          survey_questions_attributes: [
            :id, :question_text, :question_type, :position, :required,
            :settings, :_destroy,
            survey_question_options_attributes: [:id, :option_text, :position, :_destroy]
          ]
        )
      end

      def survey_json(survey, include_questions: false)
        data = {
          id: survey.external_id,
          title: survey.title,
          description: survey.description,
          anonymous: survey.anonymous,
          allow_multiple_responses: survey.allow_multiple_responses,
          closes_at: survey.closes_at,
          active: survey.active?,
          response_count: survey.response_count,
          completion_rate: survey.completion_rate,
          created_at: survey.created_at,
          updated_at: survey.updated_at
        }

        if include_questions
          data[:questions] = survey.survey_questions.alive.order(:position).map do |q|
            question_json(q)
          end
        end

        data
      end

      def question_json(question)
        {
          id: question.external_id,
          question_text: question.question_text,
          question_type: question.question_type,
          position: question.position,
          required: question.required,
          settings: question.settings,
          options: question.survey_question_options.order(:position).map do |opt|
            {
              id: opt.external_id,
              option_text: opt.option_text,
              position: opt.position
            }
          end
        }
      end

      def response_json(response)
        {
          id: response.external_id,
          user_id: response.user&.external_id,
          started_at: response.started_at,
          completed_at: response.completed_at,
          completed: response.completed?,
          answers: response.survey_answers.map do |answer|
            {
              question_id: answer.survey_question.external_id,
              text_answer: answer.text_answer,
              option_id: answer.survey_question_option&.external_id,
              rating_value: answer.rating_value
            }
          end
        }
      end

      def pagination_meta(collection)
        {
          current_page: collection.current_page,
          total_pages: collection.total_pages,
          total_count: collection.total_count,
          per_page: collection.limit_value
        }
      end
    end
  end
end
