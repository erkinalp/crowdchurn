# frozen_string_literal: true

class Api::Internal::InstallmentsController < Api::Internal::BaseController
  before_action :authenticate_user!
  after_action :verify_authorized
  before_action :set_installment, only: %i[edit update]
  before_action :authorize_user, only: %i[edit update]


  def new
    authorize Installment

    render json: InstallmentPresenter.new(seller: current_seller).new_page_props(copy_from: params[:copy_from])
  end

  def edit
    render json: InstallmentPresenter.new(seller: current_seller, installment: @installment).edit_page_props
  end

  def create
    authorize Installment
    save_installment
  end

  def update
    save_installment
  end

  private
    def save_installment
      service = SaveInstallmentService.new(seller: current_seller, params:, installment: @installment, preview_email_recipient: impersonating_user || logged_in_user)
      if service.process
        set_flash_for_installment_save(service.installment)
        render json: { installment_id: service.installment.external_id, full_url: service.installment.full_url }
      else
        render json: { message: service.error }, status: :unprocessable_entity
      end
    end

    def set_flash_for_installment_save(installment)
      if params[:publish]
        flash[:notice] = installment.shown_on_profile? ? "Email successfully published!" : "Email successfully sent!"
      elsif params[:to_be_published_at].present?
        flash[:notice] = "Email successfully scheduled!"
      end
    end

    def set_installment
      @installment = current_seller.installments.alive.find_by_external_id(params[:id])
      e404_json unless @installment
    end

    def authorize_user
      authorize @installment
    end
end
