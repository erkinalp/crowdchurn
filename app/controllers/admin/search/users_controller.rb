# frozen_string_literal: true

class Admin::Search::UsersController < Admin::Search::BaseController
  include Admin::ListPaginatedUsers

  private
    def page_title
      "Search for #{params[:query] ? params[:query].strip : "users"}"
    end

    def users_scope
      User.admin_search(params[:query]).order(created_at: :desc)
    end

    def inertia_template
      "Admin/Search/Users/Index"
    end
end
