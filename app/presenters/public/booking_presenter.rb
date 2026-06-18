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

    def cancellation_policy
      hotel_snapshot.dig("property_policy", "cancellation_policy")
    end

    def guest_info_items
      [
        { icon_path: "M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z", text: guest_email },
        { icon_path: "M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z", text: guest_phone }
      ]
    end
  end
end
