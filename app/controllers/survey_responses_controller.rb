# frozen_string_literal: true

class SurveyResponsesController < ApplicationController
  before_action :set_survey
  before_action :check_eligibility, only: [:create]

  def create
    @response = @survey.survey_responses.build(response_params)
    @response.user = current_user if user_signed_in?
    @response.respondent_cookie = cookies.signed[:respondent_id] ||= SecureRandom.uuid

    if @response.save
      redirect_to survey_response_path(@survey, @response),
                  notice: 'Response started. Please answer the questions.'
    else
      redirect_to survey_path(@survey),
                  alert: @response.errors.full_messages.join(', ')
    end
  end

  def show
    @response = @survey.survey_responses.find_by!(external_id: params[:id])

    # Ensure user can only view their own response
    unless @response.visible_to?(current_user)
      redirect_to root_path, alert: 'Not authorized'
      return
    end

    # Load questions for answering
    @questions = @survey.survey_questions.alive.order(:position)
  end

  def update
    @response = @survey.survey_responses.find_by!(external_id: params[:id])

    unless @response.visible_to?(current_user)
      redirect_to root_path, alert: 'Not authorized'
      return
    end

    # Save answers
    if save_answers(@response, params[:answers])
      # Try to complete if all required questions answered
      if @response.complete!
        redirect_to survey_path(@survey),
                    notice: 'Thank you for completing the survey!'
      else
        redirect_to survey_response_path(@survey, @response),
                    alert: 'Please answer all required questions'
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_survey
    @survey = Survey.alive.find_by!(external_id: params[:survey_id])
  end

  def check_eligibility
    unless @survey.can_respond?(
      user: current_user,
      cookie: cookies.signed[:respondent_id]
    )
      redirect_to survey_path(@survey),
                  alert: 'You have already completed this survey or it is closed'
    end
  end

  def response_params
    params.require(:survey_response).permit(:purchase_id, :subscription_id)
  end

  def save_answers(response, answers_params)
    return false unless answers_params

    answers_params.each do |question_id, answer_data|
      question = @survey.survey_questions.find_by(external_id: question_id)
      next unless question

      # Find or create answer
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
end
