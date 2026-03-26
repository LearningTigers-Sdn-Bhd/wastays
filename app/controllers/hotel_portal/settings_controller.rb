module HotelPortal
  class SettingsController < HotelPortal::BaseController
    def index
      if current_hotel
        policy = current_hotel.property_policy
        @settings = {
          hotel_status: current_hotel.status.humanize,
          onboarding_stage: onboarding_stage(current_hotel),
          check_in: policy&.check_in_time,
          check_out: policy&.check_out_time
        }
      else
        @settings = {}
      end
    end

    private

    def onboarding_stage(hotel)
      if hotel.status == "live"
        "Live"
      elsif hotel.status == "pending_review"
        "Pending Review"
      else
        "Building profile"
      end
    end
  end
end
