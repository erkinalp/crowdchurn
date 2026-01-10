# frozen_string_literal: true

class MessageTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_templateable, only: [:new, :create, :index]
  before_action :set_message_template, only: [:show, :edit, :update, :destroy, :analytics]
  before_action :authorize_template, only: [:show, :edit, :update, :destroy, :analytics]

  def index
    @templates = current_user.message_templates.alive.order(created_at: :desc)
  end

  def show
    @analytics = @template.analytics
  end

  def new
    @template = @templateable.message_templates.build
  end

  def create
    @template = @templateable.message_templates.build(template_params)
    @template.user = current_user

    if @template.save
      redirect_to @template, notice: 'Message template created successfully'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @template.update(template_params)
      redirect_to @template, notice: 'Template updated successfully'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @template.update(deleted_at: Time.current)
    redirect_to message_templates_path, notice: 'Template deleted'
  end

  def analytics
    @stats = MessageTemplateAnalyticsService.new(@template).call
  end

  private

  def set_templateable
    if params[:link_id]
      @templateable = current_user.links.find(params[:link_id])
    elsif params[:installment_id]
      @templateable = current_user.installments.find(params[:installment_id])
    else
      redirect_to root_path, alert: 'Invalid template target'
    end
  end

  def set_message_template
    @template = MessageTemplate.alive.find_by!(external_id: params[:id])
  end

  def authorize_template
    unless @template.user == current_user
      redirect_to root_path, alert: 'Not authorized'
    end
  end

  def template_params
    params.require(:message_template).permit(
      :name, :message_body, :subject, :trigger_type, :active, :priority,
      trigger_config: {},
      message_template_variants_attributes: [
        :id, :variant_name, :message_body, :subject, :weight, :_destroy
      ]
    )
  end
end
