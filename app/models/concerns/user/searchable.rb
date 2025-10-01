# frozen_string_literal: true

module User::Searchable
  extend ActiveSupport::Concern

  included do
    scope(:admin_search, lambda do |query|
      query = query.strip

      if EmailFormatValidator.valid?(query)
        where(email: query)
      else
        where(external_id: query).or(where("email LIKE ?", "%#{query}%")).or(where("name LIKE ?", "%#{query}%"))
      end
    end)
  end
end
