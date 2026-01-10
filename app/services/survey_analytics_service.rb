# frozen_string_literal: true

class SurveyAnalyticsService
  def initialize(survey)
    @survey = survey
  end

  def call
    {
      overview: overview_stats,
      questions: question_analytics,
      responses: response_analytics
    }
  end

  private

  def overview_stats
    completed = @survey.completed_responses.count

    {
      total_responses: @survey.response_count,
      completed_responses: completed,
      in_progress: @survey.response_count - completed,
      completion_rate: @survey.completion_rate,
      average_time_to_complete: average_completion_time
    }
  end

  def question_analytics
    @survey.survey_questions.alive.map do |question|
      {
        id: question.external_id,
        question: question.question_text,
        type: question.question_type,
        required: question.required,
        stats: question.answer_stats
      }
    end
  end

  def response_analytics
    return {} unless @survey.base_variant_id.present?

    # Group responses by variant if survey is variant-specific
    {
      variant_id: @survey.base_variant_id,
      variant_name: @survey.base_variant&.name,
      responses_by_date: responses_by_date
    }
  end

  def average_completion_time
    completed = @survey.survey_responses
                      .where.not(completed_at: nil)
                      .where.not(started_at: nil)

    return nil if completed.empty?

    durations = completed.pluck(:started_at, :completed_at).map do |start_time, end_time|
      end_time - start_time
    end

    avg_seconds = durations.sum / durations.size
    format_duration(avg_seconds)
  end

  def responses_by_date
    @survey.survey_responses
          .where.not(completed_at: nil)
          .group("DATE(completed_at)")
          .count
  end

  def format_duration(seconds)
    if seconds < 60
      "#{seconds.round}s"
    elsif seconds < 3600
      "#{(seconds / 60).round}m"
    else
      hours = (seconds / 3600).floor
      minutes = ((seconds % 3600) / 60).round
      "#{hours}h #{minutes}m"
    end
  end
end
