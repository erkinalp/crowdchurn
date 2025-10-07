# frozen_string_literal: true

class Admin::AffiliatesController < Admin::BaseController
  include Pagy::Backend
  include Admin::ListPaginatedUsers
  include Admin::FetchAffiliateUser

  before_action :fetch_affiliate_user, only: [:show]

  RECORDS_PER_PAGE = 25

  def index
    super do |pagination, users|
      if users.one? && params[:page].blank? && !request.format.json?
        redirect_to admin_affiliate_path(users.first)
        return
      end
    end
  end

  def show
    @title = "#{@user.display_name} affiliate on Gumroad"

    if request.format.json?
      render json: @user
    else
      render inertia: "Admin/Affiliates/Show",
             props: {
               user: @user.as_json(admin: true, impersonatable: policy([:admin, :impersonators, @user]).create?),
             }
    end
  end

  private
    def page_title
      "Search for #{params[:query] ? params[:query].strip : "affiliates"}"
    end

    def users_scope
      User.admin_search(params[:query]).joins(:direct_affiliate_accounts).distinct
    end

    def inertia_template
      "Admin/Affiliates/Index"
    end
end
