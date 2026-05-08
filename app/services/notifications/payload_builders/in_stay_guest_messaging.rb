# frozen_string_literal: true

module Notifications
  module PayloadBuilders
    class InStayGuestMessaging
      RULE_LABELS = {
        "mid_stay" => "Mid-stay check-in",
        "upsell" => "Stay enhancement",
        "activity" => "Things to do"
      }.freeze

      RULE_CONTENT = {
        "mid_stay" => {
          "headline" => "How is everything so far?",
          "body" => "We hope you are settling in well. If you need any adjustments for comfort, this is a good time to let the front desk know.",
          "suggestion_prefix" => "Current stay:"
        },
        "upsell" => {
          "headline" => "Make your stay even more enjoyable",
          "body" => "If you would like to enhance your stay, ask about available add-ons such as late checkout, room upgrades, or extra services.",
          "suggestion_prefix" => "Most guests ask for:"
        },
        "activity" => {
          "headline" => "Plan your final day",
          "body" => "Before checkout, consider planning nearby activities or dining so you can make the most of your remaining time.",
          "suggestion_prefix" => "Good idea for today:"
        }
      }.freeze

      def initialize(booking:, rule_key:, scheduled_for:)
        @booking = booking
        @rule_key = rule_key.to_s
        @scheduled_for = scheduled_for
      end

      def call
        raise ArgumentError, "Unsupported in-stay rule: #{@rule_key}" unless RULE_LABELS.key?(@rule_key)

        {
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          guest_name: @booking.guest_name,
          guest_email: @booking.guest_email,
          guest_phone: @booking.guest_phone,
          hotel_name: @booking.hotel.name,
          check_in: @booking.check_in&.iso8601,
          check_out: @booking.check_out&.iso8601,
          room_numbers: room_numbers,
          room_types: room_types,
          trigger_event: "booking_confirmed",
          notification_type: "in_stay_guest_messaging",
          rule_key: @rule_key,
          rule_label: RULE_LABELS.fetch(@rule_key),
          message_headline: RULE_CONTENT.fetch(@rule_key).fetch("headline"),
          message_body: RULE_CONTENT.fetch(@rule_key).fetch("body"),
          message_suggestion: message_suggestion,
          scheduled_for: @scheduled_for.iso8601,
          stay_nights: stay_nights
        }
      end

      private

      def room_numbers
        @booking.booking_rooms.map(&:room_number).compact_blank.join(", ")
      end

      def room_types
        @booking.booking_rooms.map do |booking_room|
          booking_room.room_type_snapshot.to_h["name"].presence || booking_room.room_type&.name
        end.compact_blank.join(", ")
      end

      def stay_nights
        [ (@booking.check_out.to_date - @booking.check_in.to_date).to_i, 0 ].max
      end

      def message_suggestion
        prefix = RULE_CONTENT.fetch(@rule_key).fetch("suggestion_prefix")
        room_bits = []
        room_bits << "Room #{room_numbers}" if room_numbers.present?
        room_bits << room_types if room_types.present?
        room_summary = room_bits.join(" · ")
        return "#{prefix} Your booking is confirmed." if room_summary.blank?

        "#{prefix} #{room_summary}."
      end
    end
  end
end
