# frozen_string_literal: true

class SurveysController < ApplicationController
  before_action :authenticate_user!, except: [:show]
  before_action :set_surveyable, only: [:new, :create]
  before_action :set_survey, only: [:show, :edit, :update, :destroy, :results]
  before_action :authorize_survey, only: [:edit, :update, :destroy, :results]

  def index
    @surveys = current_user.surveys.alive.order(created_at: :desc)
  end

  def show
    @survey = Survey.alive.find_by!(external_id: params[:id])

    # Check if user has already responded
    if user_signed_in?
      @existing_response = @survey.survey_responses.find_by(user: current_user)
    end

    # Check eligibility
    @can_respond = @survey.can_respond?(
      user: current_user,
      cookie: cookies.signed[:respondent_id]
    )
  end

  def new
    @survey = @surveyable.surveys.build
    @survey.survey_questions.build # Start with one question
  end

  def create
    @survey = @surveyable.surveys.build(survey_params)
    @survey.user = current_user if @surveyable.respond_to?(:user)

    if @survey.save
      redirect_to @survey, notice: 'Survey created successfully'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Pre-load questions and options for editing
    @survey.survey_questions.build if @survey.survey_questions.empty?
  end

  def update
    if @survey.update(survey_params)
      redirect_to @survey, notice: 'Survey updated successfully'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @survey.update(deleted_at: Time.current)
    redirect_to surveys_path, notice: 'Survey deleted'
  end

  def results
    @analytics = SurveyAnalyticsService.new(@survey).call
  end

  private

  def set_surveyable
    # Determine if this is for a Link or Installment
    if params[:link_id]
      @surveyable = Link.find(params[:link_id])
    elsif params[:installment_id]
      @surveyable = Installment.find(params[:installment_id])
    else
      redirect_to root_path, alert: 'Invalid survey target'
    end
  end

  def set_survey
    @survey = Survey.alive.find_by!(external_id: params[:id])
  end

  def authorize_survey
    unless @survey.creator?(current_user)
      redirect_to root_path, alert: 'You are not authorized to access this survey'
    end
  end

  def survey_params
    params.require(:survey).permit(
      :title, :description, :anonymous, :allow_multiple_responses,
      :closes_at, :base_variant_id,
      survey_questions_attributes: [
        :id, :question_text, :question_type, :position, :required,
        :settings, :_destroy,
        survey_question_options_attributes: [
          :id, :option_text, :position, :_destroy
        ]
      ]
    )
  end
end
