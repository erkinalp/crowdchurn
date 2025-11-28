# frozen_string_literal: true

class ChurnController < Sellers::BaseController
  layout "inertia"

  DEFAULT_END_DATE = Date.current
  DEFAULT_START_DATE = DEFAULT_END_DATE - 30.days

  def show
    authorize :churn

    LargeSeller.create_if_warranted(current_seller)

    service = CreatorAnalytics::Churn.new(seller: current_seller)

    start_date = parse_date(params[:from]) || DEFAULT_START_DATE
    end_date = parse_date(params[:to]) || DEFAULT_END_DATE

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
