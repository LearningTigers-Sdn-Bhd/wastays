module AiConcierge
  module Tools
    class ToolRegistry
    TOOL_MAP = {
      "search_booking_options" => "AiConcierge::Tools::Booking::SearchBookingOptionsTool",
      "select_booking_option" => "AiConcierge::Tools::Booking::SelectBookingOptionTool",
      "generate_booking_url" => "AiConcierge::Tools::Booking::GenerateBookingUrlTool",
      "get_hotel_policy" => "AiConcierge::Tools::HotelInformation::GetHotelPolicyTool",
      "get_booking_context" => "AiConcierge::Tools::HotelInformation::GetBookingContextTool",
      "get_general_hotel_info" => "AiConcierge::Tools::HotelInformation::GetGeneralHotelInfoTool",
      "get_hotel_faq" => "AiConcierge::Tools::HotelInformation::GetHotelFaqTool",
      "get_nearby_attractions" => "AiConcierge::Tools::HotelInformation::GetNearbyAttractionsTool",
      "get_room_type_details" => "AiConcierge::Tools::RoomInformation::GetRoomTypeDetailsTool"
    }.freeze

    def fetch(name)
      TOOL_MAP.fetch(name).constantize
    end
    end
  end
end
