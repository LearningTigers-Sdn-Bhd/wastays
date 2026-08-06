# frozen_string_literal: true

module DocumentIdentifiers
  module HotelReferences
    TOKEN_CHARSET = (("A".."Z").to_a + ("2".."9").to_a - %w[I O L]).freeze
    TOKEN_LENGTH = 6
    DOCUMENT_NUMBER_PAD_LENGTH = 5

    module_function

    def generate_confirmation_token
      loop do
        candidate = Array.new(TOKEN_LENGTH) { TOKEN_CHARSET.sample }.join
        return candidate unless BookingConfirmationToken.exists?(token: candidate)
      end
    end

    def assign_confirmation_token(record, attribute: :confirmation_token, unique_against: record.class)
      return if record.public_send(attribute).present?

      loop do
        candidate = generate_confirmation_token
        next if Array(unique_against).any? { |klass| klass.exists?(attribute => candidate) }

        record.public_send("#{attribute}=", candidate)
        break
      end
    end

    def assign_counter(record, attribute:, counter_type:)
      return if record.public_send(attribute).present?
      return if record.hotel.blank?

      record.public_send("#{attribute}=", DocumentIdentifiers::Issuer.next_number!(hotel: record.hotel, type: counter_type.to_sym))
    end

    def format(hotel:, year:, number:, type_code:)
      return nil unless year && number

      prefix = hotel&.hotel_prefix.presence || "WS"
      padded = number.to_s.rjust(DOCUMENT_NUMBER_PAD_LENGTH, "0")
      year_code = (year.to_i % 100).to_s.rjust(2, "0")
      "#{prefix}-#{year_code}#{type_code}#{padded}"
    end
  end
end
