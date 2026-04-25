# frozen_string_literal: true

# Generates an opaque, random, public-facing identifier stored directly in the
# database. Matches the Nano ID pattern already used by `PublicFile#public_id`
# and `UtmLink#permalink`: 16-character lowercase alphanumeric, unique per
# table. This is the pattern required by CONTRIBUTING.md for new models — the
# older `ExternalId` module encrypts the primary key with `ObfuscateIds`, which
# leaks record ordering and is reserved for legacy models.
module NanoExternalId
  extend ActiveSupport::Concern

  EXTERNAL_ID_LENGTH = 16
  EXTERNAL_ID_FORMAT = /\A[a-z0-9]{#{EXTERNAL_ID_LENGTH}}\z/

  included do
    validates :external_id,
              presence: true,
              format: { with: EXTERNAL_ID_FORMAT },
              uniqueness: { case_sensitive: false }

    before_validation :set_external_id
  end

  class_methods do
    def find_by_external_id(external_id)
      find_by(external_id: external_id)
    end

    def find_by_external_id!(external_id)
      find_by!(external_id: external_id)
    end

    def generate_external_id(max_retries: 10)
      retries = 0
      candidate = SecureRandom.alphanumeric(EXTERNAL_ID_LENGTH).downcase

      while exists?(external_id: candidate)
        retries += 1
        raise "Failed to generate unique external_id for #{name} after #{max_retries} attempts" if retries >= max_retries

        candidate = SecureRandom.alphanumeric(EXTERNAL_ID_LENGTH).downcase
      end

      candidate
    end
  end

  private
    def set_external_id
      return if external_id.present?

      self.external_id = self.class.generate_external_id
    end
end
