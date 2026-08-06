# frozen_string_literal: true

module DocumentIdentifiers
  # Single source of folio numbers. Wraps the hotel folio counter but floors it
  # at the hotel's current max folio_number, so a counter that has drifted behind
  # bulk-loaded folios (snapshot / seed / demo reseed) can never reissue a number
  # that already exists. Self-heals: the first call past a stale counter advances
  # it past the max, and subsequent calls run straight off the counter again.
  class NextFolioNumber
    def self.call(hotel:)
      issue(hotel:).number
    end

    def self.issue(hotel:)
      DocumentIdentifiers::Issuer.issue!(hotel:, type: :folio)
    end
  end
end
