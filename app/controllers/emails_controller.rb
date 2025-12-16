# frozen_string_literal: true

class EmailsController < Sellers::BaseController
  # TODO: Remove set_body_id_as_app once all email pages are migrated to Inertia
  before_action :set_body_id_as_app, only: %i[index]
  before_action :set_inertia_layout, only: %i[published scheduled]

  def index
    authorize Installment

    create_user_event("emails_view")

    # TODO: Remove this redirect logic once all email pages are migrated to Inertia
    # For now, /emails/drafts, /emails/new, /emails/:id/edit are still handled by react-router
    if request.path == emails_path
      default_tab = Installment.alive.not_workflow_installment.scheduled.where(seller: current_seller).exists? ? "scheduled" : "published"
      redirect_to "#{emails_path}/#{default_tab}", status: :moved_permanently
    end
  end

  def published
    authorize Installment, :index?
    create_user_event("emails_view")

    presenter = PaginatedInstallmentsPresenter.new(seller: current_seller, type: Installment::PUBLISHED, page: 1)
    render inertia: "Emails/Published", props: presenter.props
  end

  def scheduled
    authorize Installment, :index?
    create_user_event("emails_view")

    presenter = PaginatedInstallmentsPresenter.new(seller: current_seller, type: Installment::SCHEDULED, page: 1)
    render inertia: "Emails/Scheduled", props: presenter.props
  end

  private
    def set_title
      @title = "Emails"
    end

    def set_inertia_layout
      self.class.layout "inertia"
    end
end
