# frozen_string_literal: true

module Public
  class BookingPresenter < SimpleDelegator
    def initialize(booking, view_context)
      @booking = booking
      @view_context = view_context
      super(booking)
    end

    def guest_first_name
      guest_name.to_s.split.first
    end

    def formatted_check_in
      check_in.strftime("%b %d, %Y")
    end

    def formatted_check_out
      check_out.strftime("%b %d, %Y")
    end

    def stay_duration
      @view_context.pluralize((check_out.to_date - check_in.to_date).to_i, "Night")
    end

    def check_in_time
      hotel_snapshot.dig("property_policy", "check_in_time") || "2:00 PM"
    end

    def check_out_time
      hotel_snapshot.dig("property_policy", "check_out_time") || "12:00 PM"
    end

    def total_amount_display
      @view_context.number_to_currency(total_amount, unit: "RM ", precision: 2)
    end

    # The booking's own snapshot is the authority — this used to read
    # `hotel_snapshot["property_policy"]`, a key `Hotel#booking_snapshot` never
    # writes, so the policy silently never rendered.
    def cancellation_summary
      @cancellation_summary ||= Cancellations::PolicySummary.for_record(
        @booking,
        legacy_text: hotel_snapshot&.dig("property_policy", "cancellation_policy")
      )
    end

    def cancellation_policy
      cancellation_summary.to_text
    end

    def guest_info_items
      [
        {
          icon_svg: @view_context.cached_icon("mail", library: "lucide", class: "w-3.5 h-3.5 text-[#d9c5a0]"),
          text: guest_email
        },
        {
          icon_svg: @view_context.cached_icon("phone", library: "phosphor", class: "w-3.5 h-3.5 text-[#d9c5a0]"),
          text: guest_phone
        }
      ]
    end
  end
end
