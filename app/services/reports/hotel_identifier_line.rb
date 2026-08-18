# frozen_string_literal: true

module Reports
  # The registrations that identify the party issuing a document, set as one line under
  # the masthead address.
  #
  # Shared so the line cannot say one thing on an invoice and another on a voucher. Every
  # registration is named whether or not the issuer holds one — a dash says the number is
  # absent, where dropping the label leaves a reader unable to tell an unregistered issuer
  # from a document that failed to print what it had.
  #
  # Callers pass resolved values rather than a hotel: an invoice reads them from its
  # issue-time snapshot, a voucher from the live hotel.
  module HotelIdentifierLine
    def self.call(tin:, sst:, tourism_tax:)
      [
        [ "TIN", tin ],
        [ "SST", sst ],
        [ "Tourism Tax", tourism_tax ]
      ].map { |label, value| "#{label}: #{value.presence || '-'}" }.join(" · ")
    end

    def self.for_hotel(hotel)
      call(
        tin: hotel.tin,
        sst: hotel.sst_registration_number,
        tourism_tax: hotel.tourism_tax_registration_number
      )
    end
  end
end
