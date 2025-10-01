# fron

class Admin::Search::UsersController < Admin::Search::BaseController
  include Pagy::Backend

  before_action { @title = "Search for #{params[:query].strip}" }

  def index
    pagination, users = pagy_countless(
      User.admin_search(params[:query]).order(created_at: :desc),
      limit: params[:per_page] || RECORDS_PER_PAGE,
      page: params[:page],
      countless_minimal: true
    )

    if users.one? && params[:page].blank?
      redirect_to admin_user_path(users.first)
    else
      render  inertia: 'Admin/Search/Users/Index',
              props: inertia_props(
                users: InertiaRails.merge { users.map do |user|
                  user.as_json_for_admin(impersonatable: policy([:admin, :impersonators, user]).create?)
                end },
                pagination:
              )
    end
  end
end
