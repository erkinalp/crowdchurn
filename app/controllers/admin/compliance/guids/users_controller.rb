# frozen_string_literal: true

class Admin::Compliance::Guids::UsersController < Admin::Compliance::Guids::BaseController
  include Admin::ListPaginatedUsers

  private
    def page_title
      guid
    end

    def users_scope
      User.includes(:purchases).where(id: Event.by_browser_guid(guid).select(:user_id))
    end

    def inertia_template
      "Admin/Compliance/Guids/Users/Index"
    end

    def guid
      params[:guid_id]
    end
end
