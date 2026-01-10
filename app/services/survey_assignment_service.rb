# frozen_string_literal: true

# Service for assigning surveys/tasks to users based on their variant/tier
# Optimized for high-volume crowdsourcing scenarios
class SurveyAssignmentService
  def initialize(user:, purchase: nil, subscription: nil)
    @user = user
    @purchase = purchase
    @subscription = subscription
  end

  # Get available surveys/tasks for this user
  # Returns surveys they haven't completed yet
  def available_surveys
    # Determine which variants this user has access to
    variant_ids = accessible_variant_ids

    # Find active surveys for these variants that user hasn't completed
    Survey.alive
          .active
          .where(base_variant_id: variant_ids)
          .where.not(id: completed_survey_ids)
          .includes(:survey_questions)
          .order(created_at: :desc)
  end

  # Get surveys user has in progress
  def in_progress_surveys
    survey_ids = SurveyResponse
                   .where(user: @user)
                   .in_progress
                   .pluck(:survey_id)

    Survey.where(id: survey_ids)
          .includes(:survey_questions)
  end

  # Get next available survey/task for user
  # Useful for sequential task assignment
  def next_available_survey
    available_surveys.first
  end

  # Batch assign surveys to multiple users
  # Optimized for bulk task distribution
  def self.batch_assign(survey:, users:)
    # Pre-filter users who already completed
    user_ids = users.pluck(:id)
    completed_user_ids = SurveyResponse
                          .where(survey: survey, user_id: user_ids)
                          .where.not(completed_at: nil)
                          .pluck(:user_id)

    eligible_users = users.where.not(id: completed_user_ids)

    # Create response records in batch
    response_records = eligible_users.map do |user|
      {
        survey_id: survey.id,
        user_id: user.id,
        started_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    SurveyResponse.insert_all(response_records) if response_records.any?

    eligible_users.count
  end

  # Check if user can access this survey based on their purchases/subscriptions
  def can_access?(survey)
    return false unless survey.active?

    # If survey is for a specific variant, check user has access
    if survey.base_variant_id.present?
      accessible_variant_ids.include?(survey.base_variant_id)
    else
      # If survey is for a product/post, check ownership
      case survey.surveyable_type
      when 'Link'
        # User must have purchased the product
        @purchase&.link_id == survey.surveyable_id ||
          @user.purchases.successful.exists?(link_id: survey.surveyable_id)
      when 'Installment'
        # User must have access to the post
        @subscription&.link_id == survey.surveyable.link_id ||
          @user.subscriptions.active.exists?(link_id: survey.surveyable.link_id)
      else
        false
      end
    end
  end

  private

  def accessible_variant_ids
    variant_ids = []

    # Get variants from purchases
    if @purchase
      variant_ids += @purchase.variant_attributes.pluck(:id)
    end

    # Get variants from subscriptions
    if @subscription
      variant_ids += @subscription.purchases
                                  .successful
                                  .joins(:base_variants_purchases)
                                  .pluck('base_variants_purchases.base_variant_id')
    end

    # Get all variants from all user's active subscriptions
    variant_ids += @user.subscriptions
                        .active
                        .joins(purchases: :base_variants_purchases)
                        .pluck('base_variants_purchases.base_variant_id')

    variant_ids.uniq.compact
  end

  def completed_survey_ids
    @completed_survey_ids ||= SurveyResponse
                                .where(user: @user)
                                .where.not(completed_at: nil)
                                .pluck(:survey_id)
  end
end
