# frozen_string_literal: true

class ChurnController < Sellers::BaseController
  layout "inertia"

  def show
    authorize :churn

    LargeSeller.create_if_warranted(current_seller)

    service = CreatorAnalytics::Churn.new(seller: current_seller)

    start_date = parse_date(params[:from]) || 30.days.ago
    end_date = parse_date(params[:to]) || Date.current

    render(
      inertia: "Churn/Show",
      props: {
        churn: service.generate_data(start_date:, end_date:)
      }
    )
  end

  private
    def parse_date(date)
      Date.parse(date.to_s)
    rescue Date::Error
      nil
    end
end
