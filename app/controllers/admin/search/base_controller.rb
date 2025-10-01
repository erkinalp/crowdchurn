# frozen_string_literal: true

class Admin::Search::BaseController < Admin::BaseController
  RECORDS_PER_PAGE = 25
  private_constant :RECORDS_PER_PAGE

  layout 'admin_inertia'
end
