module AiConciergeV3
  class ToolRegistry
    TOOL_MAP = {
      "search_booking_options" => "AiConciergeV3::Tools::Booking::SearchBookingOptionsTool",
      "select_booking_option" => "AiConciergeV3::Tools::Booking::SelectBookingOptionTool",
      "generate_booking_url" => "AiConciergeV3::Tools::Booking::GenerateBookingUrlTool",
      "get_hotel_policy" => "AiConciergeV3::Tools::HotelInformation::GetHotelPolicyTool",
      "get_booking_context" => "AiConciergeV3::Tools::HotelInformation::GetBookingContextTool",
      "get_general_hotel_info" => "AiConciergeV3::Tools::HotelInformation::GetGeneralHotelInfoTool",
      "get_hotel_faq" => "AiConciergeV3::Tools::HotelInformation::GetHotelFaqTool",
      "get_nearby_attractions" => "AiConciergeV3::Tools::HotelInformation::GetNearbyAttractionsTool",
      "get_room_type_details" => "AiConciergeV3::Tools::RoomInformation::GetRoomTypeDetailsTool",
      "get_room_type_faq" => "AiConciergeV3::Tools::RoomInformation::GetRoomTypeFaqTool"
    }.freeze

    def fetch(name)
      TOOL_MAP.fetch(name).constantize
    end
  end
end
