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
        {
          icon_svg: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-3.5 h-3.5 text-[#d9c5a0]"><path d="m22 7-8.991 5.727a2 2 0 0 1-2.009 0L2 7" /><rect x="2" y="4" width="20" height="16" rx="2" /></svg>',
          text: guest_email
        },
        {
          icon_svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class="w-3.5 h-3.5 text-[#d9c5a0]"><rect width="256" height="256" fill="none"/><path d="M164.39,145.34a8,8,0,0,1,7.59-.69l47.16,21.13a8,8,0,0,1,4.8,8.3A48.33,48.33,0,0,1,176,216,136,136,0,0,1,40,80,48.33,48.33,0,0,1,81.92,32.06a8,8,0,0,1,8.3,4.8l21.13,47.2a8,8,0,0,1-.66,7.53L89.32,117a7.93,7.93,0,0,0-.54,7.81c8.27,16.93,25.77,34.22,42.75,42.41a7.92,7.92,0,0,0,7.83-.59Z" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>',
          text: guest_phone
        }
      ]
    end
  end
end
