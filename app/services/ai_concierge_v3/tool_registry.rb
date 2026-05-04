module AiConciergeV3
  class ToolRegistry
    TOOL_MAP = {
      "search_booking_options" => "AiConciergeV3::Tools::SearchBookingOptionsTool",
      "select_booking_option" => "AiConciergeV3::Tools::SelectBookingOptionTool",
      "generate_booking_url" => "AiConciergeV3::Tools::GenerateBookingUrlTool",
      "get_hotel_policy" => "AiConciergeV3::Tools::GetHotelPolicyTool",
      "get_booking_context" => "AiConciergeV3::Tools::GetBookingContextTool"
    }.freeze

    def fetch(name)
      TOOL_MAP.fetch(name).constantize
    end
  end
end
