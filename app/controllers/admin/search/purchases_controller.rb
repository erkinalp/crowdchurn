# fron

class Admin::Search::PurchasesController < Admin::Search::BaseController
  include Pagy::Backend

  layout "admin_inertia"

  head_title "Purchase results"

  def index
    pagination, purchases = pagy_countless(
      AdminSearchService.new.search_purchases(
        query: params[:query].strip,
        product_title_query: params[:product_title_query]&.strip,
        purchase_status: params[:purchase_status],
      ),
      limit: params[:per_page] || RECORDS_PER_PAGE,
      page: params[:page],
      countless_minimal: true
    )

    if purchases.one? && params[:page].blank?
      redirect_to admin_purchase_path(purchases.first)
    else
      render inertia: 'Admin/Search/Purchases/Index',
             props: inertia_props(
               purchases: InertiaRails.merge { purchases.as_json_for_admin },
               pagination:,
               query: params[:query],
               product_title_query: params[:product_title_query],
               purchase_status: params[:purchase_status]
            )
    end
  end
end
