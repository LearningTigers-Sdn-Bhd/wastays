# frozen_string_literal: true

module PostalAddresses
  class Presenter
    FIELDS = %w[address_line1 address_line2 city state postal_code country].freeze
    REQUIRED_FIELDS = %w[address_line1 city country].freeze

    def self.from_guest(guest)
      new(
        address_line1: guest&.home_address,
        city: guest&.city,
        state: printable_state(guest&.state_code),
        postal_code: guest&.postal_code,
        country: guest&.address_country.presence || guest&.country
      )
    end

    def self.from_booking(booking)
      new(
        address_line1: booking&.guest_home_address,
        city: booking&.guest_city,
        state: printable_state(booking&.guest_state_code),
        postal_code: booking&.guest_postal_code,
        country: booking&.guest_address_country.presence || booking&.guest_country
      )
    end

    def self.from_booking_guest(booking_guest, fallback_booking: nil)
      new(
        address_line1: booking_guest&.home_address_snapshot.presence || fallback_booking&.guest_home_address,
        city: booking_guest&.city_snapshot.presence || fallback_booking&.guest_city,
        state: printable_state(booking_guest&.state_code_snapshot.presence || fallback_booking&.guest_state_code),
        postal_code: booking_guest&.postal_code_snapshot.presence || fallback_booking&.guest_postal_code,
        country: booking_guest&.address_country_snapshot.presence ||
          fallback_booking&.guest_address_country.presence || fallback_booking&.guest_country
      )
    end

    def self.from_snapshot(snapshot)
      new(snapshot.to_h)
    end

    def self.printable_state(state_code)
      return if state_code.blank? || state_code.to_s == EInvoice::MalaysiaStates::NOT_APPLICABLE

      EInvoice::MalaysiaStates.name_for(state_code) || state_code
    end

    def initialize(values = nil, **attributes)
      values = (values || {}).to_h.merge(attributes).stringify_keys
      @values = FIELDS.index_with { |field| values[field].to_s.strip.presence }
    end

    def complete? = REQUIRED_FIELDS.all? { |field| @values[field].present? }
    def missing? = @values.values.all?(&:blank?)
    def incomplete? = !missing? && !complete?

    def status_label
      return "Address missing" if missing?
      return "Address incomplete" if incomplete?

      "Address complete"
    end

    def lines
      street_lines + [
        [ @values["postal_code"], @values["city"] ].compact_blank.join(" ").presence,
        [ @values["state"], @values["country"] ].compact_blank.join(", ").presence
      ].compact_blank
    end

    def display = lines.join("\n").presence

    def snapshot = FIELDS.index_with { |field| @values[field] }

    private

    def street_lines
      [ @values["address_line1"], @values["address_line2"] ]
        .compact_blank.flat_map { |line| line.lines(chomp: true) }.compact_blank
    end
  end
end
