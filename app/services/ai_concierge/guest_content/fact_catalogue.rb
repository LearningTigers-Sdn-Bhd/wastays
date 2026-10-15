# frozen_string_literal: true

module AiConcierge
  module GuestContent
    # Builds the operational facts that the concierge can answer without search.
    # Values are guest-safe: Wi-Fi credentials and after-hours private contacts
    # are intentionally excluded.
    class FactCatalogue
      def initialize(hotel:)
        @hotel = hotel
      end

      def call
        {
          "arrival_instructions" => arrival_fact,
          "departure_instructions" => departure_fact,
          "directions" => directions_fact,
          "transportation" => transportation_fact,
          "parking" => parking_fact,
          "front_desk_contact" => front_desk_contact_fact,
          "front_desk_hours" => front_desk_hours_fact,
          "emergency_contact" => emergency_fact,
          "wifi_availability" => wifi_fact
        }.compact
      end

      private

      attr_reader :hotel

      def arrival_fact
        parts = []
        fields = []
        if policy&.check_in_time.present?
          parts << "Check-in is from #{clock(policy.check_in_time)}."
          fields << "property_policies.check_in_time"
        end
        if instructions&.arrival_instructions.present?
          parts << sentence(instructions.arrival_instructions)
          fields << "hotel_guest_instructions.arrival_instructions"
        end
        entry(parts, "arrival_departure", fields)
      end

      def departure_fact
        parts = []
        fields = []
        if policy&.check_out_time.present?
          parts << "Check-out is by #{clock(policy.check_out_time)}."
          fields << "property_policies.check_out_time"
        end
        if instructions&.departure_instructions.present?
          parts << sentence(instructions.departure_instructions)
          fields << "hotel_guest_instructions.departure_instructions"
        end
        entry(parts, "arrival_departure", fields)
      end

      def directions_fact
        return unless transport&.section_configured?("directions")

        parts = []
        fields = []
        append_travel(parts, fields, "The airport", :airport_distance_km, :airport_travel_minutes)
        append_travel(parts, fields, "The train station", :station_distance_km, :station_travel_minutes)
        append_travel(parts, fields, "The city centre", :city_centre_distance_km, :city_centre_travel_minutes)
        append(parts, fields, transport.directions, "hotel_transport_details.directions")
        entry(parts, "transport_details", fields)
      end

      def transportation_fact
        return unless transport&.section_configured?("transportation")

        parts = []
        fields = [ "hotel_transport_details.airport_transfer_offered" ]
        if transport.airport_transfer_offered?
          parts << "The hotel offers an airport transfer."
          if transport.airport_transfer_price.present?
            parts << "The transfer costs #{money(transport.airport_transfer_price)}."
            fields << "hotel_transport_details.airport_transfer_price"
          end
          if transport.airport_transfer_lead_hours.present?
            lead = transport.airport_transfer_lead_hours
            parts << (lead.zero? ? "No advance notice is required." : "Book at least #{lead} #{'hour'.pluralize(lead)} ahead.")
            fields << "hotel_transport_details.airport_transfer_lead_hours"
          end
          append_labeled(parts, fields, "Pickup point", transport.pickup_point, "hotel_transport_details.pickup_point")
        else
          parts << "The hotel does not offer an airport transfer."
        end
        append_labeled(parts, fields, "Shuttle", transport.shuttle_schedule, "hotel_transport_details.shuttle_schedule")
        append_labeled(parts, fields, "Nearest public transport stop", transport.nearest_transit_stop,
          "hotel_transport_details.nearest_transit_stop")
        append(parts, fields, transport.transport_notes, "hotel_transport_details.transport_notes")
        entry(parts, "transport_details", fields)
      end

      def parking_fact
        return unless transport&.section_configured?("parking")

        fields = [ "hotel_transport_details.parking_availability" ]
        return entry([ "The hotel does not provide guest parking." ], "transport_details", fields) unless transport.parking?

        parts = [ "#{transport.parking_label} guest parking is available." ]
        append_labeled(parts, fields, "Parking type", transport.parking_type_label, "hotel_transport_details.parking_type")
        if transport.parking_price_unit == "free"
          parts << "Parking is free."
          fields << "hotel_transport_details.parking_price_unit"
        elsif transport.parking_price.present?
          unit = transport.price_unit_label.to_s.downcase.presence
          parts << [ "Parking costs #{money(transport.parking_price)}", unit ].compact.join(" ") + "."
          fields.concat(%w[hotel_transport_details.parking_price hotel_transport_details.parking_price_unit])
        end
        append_labeled(parts, fields, "Spaces", transport.parking_spaces, "hotel_transport_details.parking_spaces")
        if transport.parking_height_limit_m.present?
          parts << "The height limit is #{format_number(transport.parking_height_limit_m)} m."
          fields << "hotel_transport_details.parking_height_limit_m"
        end
        if transport.parking_ev_charging?
          parts << "EV charging is available."
          fields << "hotel_transport_details.parking_ev_charging"
        end
        if transport.parking_booking_required?
          parts << "Advance parking booking is required."
          fields << "hotel_transport_details.parking_booking_required"
        end
        append(parts, fields, transport.parking_notes, "hotel_transport_details.parking_notes")
        entry(parts, "transport_details", fields)
      end

      def front_desk_contact_fact
        parts = []
        fields = []
        append_labeled(parts, fields, "Front desk phone", contact&.front_desk_phone.presence || hotel.contact_phone,
          contact&.front_desk_phone.present? ? "hotel_guest_contacts.front_desk_phone" : "hotels.contact_phone")
        append_labeled(parts, fields, "Extension", contact&.front_desk_extension, "hotel_guest_contacts.front_desk_extension")
        append_labeled(parts, fields, "WhatsApp", contact&.front_desk_whatsapp.presence || hotel.whatsapp_number,
          contact&.front_desk_whatsapp.present? ? "hotel_guest_contacts.front_desk_whatsapp" : "hotels.whatsapp_number")
        append_labeled(parts, fields, "Email", contact&.front_desk_email.presence || hotel.contact_email,
          contact&.front_desk_email.present? ? "hotel_guest_contacts.front_desk_email" : "hotels.contact_email")
        entry(parts, "guest_contact", fields)
      end

      def front_desk_hours_fact
        return unless contact

        if contact.front_desk_open_24h?
          entry([ "The front desk is open 24 hours." ], "guest_contact", [ "hotel_guest_contacts.front_desk_open_24h" ])
        elsif contact.front_desk_opens_at.present? && contact.front_desk_closes_at.present?
          entry(
            [ "The front desk is open from #{clock(contact.front_desk_opens_at)} to #{clock(contact.front_desk_closes_at)}." ],
            "guest_contact",
            %w[hotel_guest_contacts.front_desk_opens_at hotel_guest_contacts.front_desk_closes_at]
          )
        end
      end

      def emergency_fact
        return unless contact&.emergency_present?

        parts = []
        fields = []
        append(parts, fields, contact.emergency_instructions, "hotel_guest_contacts.emergency_instructions")
        append_labeled(parts, fields, "Hotel emergency contact", contact.emergency_phone, "hotel_guest_contacts.emergency_phone")
        append_labeled(parts, fields, "Emergency services", contact.emergency_services_number,
          "hotel_guest_contacts.emergency_services_number")
        entry(parts, "guest_contact", fields)
      end

      def wifi_fact
        return unless hotel.hotel_wifi_networks.for_guest.exists?

        entry(
          [ "Guest Wi-Fi is available. Connection details become available after check-in." ],
          "wifi_networks",
          [ "hotel_wifi_networks.access_scope" ]
        )
      end

      def append_travel(parts, fields, label, distance_attribute, minutes_attribute)
        distance = transport.public_send(distance_attribute)
        minutes = transport.public_send(minutes_attribute)
        return if distance.blank? && minutes.blank?

        detail = []
        detail << "#{distance} km away" if distance.present?
        detail << "about #{minutes} min by road" if minutes.present?
        parts << "#{label} is #{detail.to_sentence}."
        fields << "hotel_transport_details.#{distance_attribute}" if distance.present?
        fields << "hotel_transport_details.#{minutes_attribute}" if minutes.present?
      end

      def append(parts, fields, value, field)
        return if value.blank?

        parts << sentence(value)
        fields << field
      end

      def append_labeled(parts, fields, label, value, field)
        return if value.blank?

        parts << "#{label}: #{value}."
        fields << field
      end

      def entry(parts, source, fields)
        text = parts.compact_blank.join(" ").presence
        return unless text

        { "text" => text, "source" => source, "fields" => fields.uniq }
      end

      def sentence(value)
        text = value.to_s.strip
        text.match?(/[.!?]\z/) ? text : "#{text}."
      end

      def clock(value)
        parsed = value.respond_to?(:strftime) ? value : Time.find_zone("UTC").parse(value.to_s)
        parsed.strftime("%-I:%M %p")
      rescue ArgumentError, NoMethodError
        value.to_s
      end

      def money(value)
        CurrencyFormatter.format(value, currency: hotel.default_currency, unit: :code)
      end

      def format_number(value)
        value.to_d.frac.zero? ? value.to_i.to_s : value.to_s("F")
      end

      def policy = hotel.property_policy
      def instructions = hotel.guest_instruction
      def contact = hotel.guest_contact
      def transport = hotel.transport_detail
    end
  end
end
