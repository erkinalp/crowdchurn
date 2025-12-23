# frozen_string_literal: true

class PaginatedInstallmentsPresenter
  include Pagy::Backend

  PER_PAGE = 25
  private_constant :PER_PAGE

  def initialize(seller:, type:, page: nil, query: nil)
    @type = type
    @seller = seller
    @page = [page.to_i, 1].max
    @query = query&.strip

    raise ArgumentError, "Invalid type" unless type.in? [Installment::PUBLISHED, Installment::SCHEDULED, Installment::DRAFT]
  end

  def props
    if query.blank?
      # Always include :seller (needed for full_url -> user -> seller.presence)
      # Only include :installment_rule for scheduled/draft (not needed for published)
      installments = Installment.includes(:seller)
      installments = installments.includes(:installment_rule) if type != Installment::PUBLISHED
      installments = installments.ordered_updates(seller, type).public_send(type)
      installments = installments.unscope(:order).order("installment_rules.to_be_published_at ASC") if type == Installment::SCHEDULED
      pagination, installments = pagy_countless(installments, page:, limit: PER_PAGE, overflow: :empty_page)
    else
      offset = (page - 1) * PER_PAGE
      search_options = {
        exclude_deleted: true,
        type:,
        exclude_workflow_installments: true,
        seller:,
        q: query,
        fields: %w[name message],
        from: offset,
        size: PER_PAGE,
        sort: [:_score, { created_at: :desc }, { id: :desc }]
      }
      es_search = InstallmentSearchService.search(search_options)
      # Include associations to avoid N+1 queries
      includes_list = [:seller]
      includes_list << :installment_rule if type != Installment::PUBLISHED
      installments = es_search.records.includes(*includes_list).load
      can_paginate_further = es_search.results.total > (offset + PER_PAGE)
      pagination = {
        page_name: "page",
        current_page: page,
        previous_page: page > 1 ? page - 1 : nil,
        next_page: can_paginate_further ? page + 1 : nil
      }
    end

    installments_data = installments.map { InstallmentPresenter.new(seller:, installment: _1).props }

    {
      installments: InertiaRails.scroll(pagination) { installments_data },
    }
  end

  private
    attr_reader :seller, :type, :page, :query
end
