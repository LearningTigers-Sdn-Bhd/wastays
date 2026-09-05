# frozen_string_literal: true

module EInvoice
  # LHDN accepts two buyer identifiers only: a MyKad (NRIC) or a passport.
  # A guest who holds a foreign national identity card must give a passport
  # number, because the national card is not a valid LHDN identifier.
  #
  # guest values ──▶ resolver ──▶ { LHDN document type, number }
  class GuestIdentityResolver
    Result = Data.define(:source_type, :document_type, :document_number) do
      def missing_passport?
        source_type == "national_id" && document_number.blank?
      end
    end

    def self.for_booking(booking)
      from_values(
        document_type: booking.guest_document_type,
        document_number: booking.guest_government_id,
        passport_number: booking.guest_passport_number,
        country: booking.guest_country
      )
    end

    def self.for_guest(guest)
      from_values(
        document_type: guest.document_type,
        document_number: guest.safely_read_encrypted(:government_id),
        passport_number: guest.safely_read_encrypted(:passport_number),
        country: guest.country
      )
    end

    def self.from_values(document_type:, document_number:, passport_number: nil, country: nil)
      source_type = GuestIdentityDocuments::NormalizeType.call(value: document_type, country: country)

      Result.new(
        source_type: source_type,
        document_type: lhdn_type(source_type),
        document_number: source_type == "national_id" ? passport_number : document_number
      )
    end

    def self.lhdn_type(source_type)
      case source_type
      when "malaysian_nric" then "ic"
      when "national_id", "passport" then "passport"
      end
    end
    private_class_method :lhdn_type
  end
end
