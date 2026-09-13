# frozen_string_literal: true

class CrowdsourcingController < ApplicationController
  before_action :authenticate_user!

  def index
    @surveys_count = current_user.surveys.count
    @active_surveys = current_user.surveys.alive.where("closes_at > ? OR closes_at IS NULL", Time.current).count

    @templates_count = current_user.message_templates.count
    @active_templates = current_user.message_templates.where(active: true).count

    @total_responses = SurveyAnalyticsService.new(nil).total_responses_for_user(current_user)
    @messages_sent = AutomatedMessage.for_creator(current_user).count
  end
end
