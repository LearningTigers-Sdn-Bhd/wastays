require "rails_helper"

RSpec.describe AiConciergeV3::Tools::HotelInformation::GetHotelFaqTool do
  it "returns the full formatted hotel faq when present" do
    hotel = create(:hotel, faq: [
      {
        "section_name" => "General",
        "items" => [
          {
            "question" => "Do you offer airport transfers?",
            "answer" => "Yes, on request."
          },
          {
            "question" => "What time is breakfast?",
            "answer" => "Breakfast is served from 7 AM to 10 AM."
          }
        ]
      },
      {
        "section_name" => "Dining",
        "items" => [
          {
            "question" => "Do you serve halal food?",
            "answer" => "Yes, selected options are available."
          }
        ]
      }
    ])

    result = described_class.new(hotel: hotel).call

    expect(result).to eq(
      "success" => true,
      "faq_text" => [
        "General",
        "- Q: Do you offer airport transfers?\n  A: Yes, on request.",
        "- Q: What time is breakfast?\n  A: Breakfast is served from 7 AM to 10 AM.",
        "",
        "Dining",
        "- Q: Do you serve halal food?\n  A: Yes, selected options are available."
      ].join("\n"),
      "source" => "hotel_faq"
    )
  end

  it "returns an unavailable payload when faq is blank" do
    hotel = create(:hotel)

    result = described_class.new(hotel: hotel).call

    expect(result).to eq(
      "success" => false,
      "faq_text" => nil,
      "source" => "hotel_faq"
    )
  end

  it "ignores malformed sections and blank faq items" do
    hotel = create(:hotel, faq: [
      "invalid",
      {
        "section_name" => "General",
        "items" => [
          {
            "question" => "",
            "answer" => ""
          },
          {
            "question" => "Is parking available?",
            "answer" => "Yes."
          }
        ]
      },
      {
        "section_name" => "",
        "items" => [
          {
            "question" => "Do you have WiFi?",
            "answer" => "Free WiFi is available throughout the hotel."
          }
        ]
      }
    ])

    result = described_class.new(hotel: hotel).call

    expect(result).to eq(
      "success" => true,
      "faq_text" => [
        "General",
        "- Q: Is parking available?\n  A: Yes.",
        "",
        "- Q: Do you have WiFi?\n  A: Free WiFi is available throughout the hotel."
      ].join("\n"),
      "source" => "hotel_faq"
    )
  end
end
