require "rails_helper"

RSpec.describe AiConcierge::Tools::Booking::SelectBookingOptionTool do
  let(:suggested_options) do
    [
      {
        "room_type_name" => "Garden Prestige Suite",
        "options" => [
          { "position" => 1, "selection_id" => "room_type_1_option_1", "check_in" => "2026-08-01" },
          { "position" => 2, "selection_id" => "room_type_1_option_2", "check_in" => "2026-08-02" }
        ]
      },
      {
        "room_type_name" => "Deluxe Room",
        "options" => [
          { "position" => 1, "selection_id" => "room_type_2_option_1", "check_in" => "2026-08-01" },
          { "position" => 2, "selection_id" => "room_type_2_option_2", "check_in" => "2026-08-03" }
        ]
      }
    ]
  end

  it "selects a valid option by room type name and position" do
    result = described_class.new(
      option_number: 2,
      suggested_options: suggested_options,
      suggestion_set_version: 3,
      message: "Garden Prestige Suite option 2"
    ).call

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_1_option_2")
  end

  it "finds the room type when the guest wraps its name in a sentence" do
    result = described_class.new(
      option_number: nil,
      suggested_options: suggested_options,
      suggestion_set_version: 3,
      message: "i want to book at garden prestige for the standard rate"
    ).call

    expect(result["success"]).to be(false)
    expect(result["error"]).to eq("room_type_requires_option_number")
    expect(result["room_type_name"]).to eq("Garden Prestige Suite")
  end

  it "returns an ambiguous option result when multiple groups share the same number" do
    result = described_class.new(
      option_number: 2,
      suggested_options: suggested_options,
      suggestion_set_version: 3,
      message: "option 2"
    ).call

    expect(result["success"]).to be(false)
    expect(result["error"]).to eq("ambiguous_option_selection")
    expect(result["room_type_names"]).to include("Garden Prestige Suite", "Deluxe Room")
  end

  it "selects the only visible option when the user names the room type" do
    result = described_class.new(
      option_number: nil,
      suggested_options: [
        {
          "room_type_name" => "Executive Penthouse",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_9_option_1", "check_in" => "2026-06-06" }
          ]
        }
      ],
      suggestion_set_version: 3,
      message: "can i choose executive penthouse"
    ).call

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_9_option_1")
  end

  it "selects the only visible option with reordered room type shorthand" do
    result = described_class.new(
      option_number: nil,
      suggested_options: [
        {
          "room_type_name" => "Ocean Villa King",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_7_option_1", "check_in" => "2026-06-06" }
          ]
        }
      ],
      suggestion_set_version: 3,
      message: "king ocean"
    ).call

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_7_option_1")
  end

  it "selects the only visible option with a small typo" do
    result = described_class.new(
      option_number: nil,
      suggested_options: [
        {
          "room_type_name" => "Executive Penthouse",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_8_option_1", "check_in" => "2026-06-06" }
          ]
        }
      ],
      suggestion_set_version: 3,
      message: "excutive penthouse"
    ).call

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_8_option_1")
  end

  it "asks for option number when a room type has multiple visible options" do
    result = described_class.new(
      option_number: nil,
      suggested_options: suggested_options,
      suggestion_set_version: 3,
      message: "garden prestige suite"
    ).call

    expect(result["success"]).to be(false)
    expect(result["error"]).to eq("room_type_requires_option_number")
    expect(result["room_type_name"]).to eq("Garden Prestige Suite")
  end

  it "extracts option number deterministically from the raw message" do
    result = described_class.new(
      option_number: nil,
      suggested_options: [
        {
          "room_type_name" => "Garden Prestige Suite",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_1_option_1", "check_in" => "2026-08-21" }
          ]
        }
      ],
      suggestion_set_version: 3,
      message: "i chose option 1"
    ).call

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_1_option_1")
  end

  it "uses pending date context to auto-select when the room type reply narrows to one option" do
    result = described_class.new(
      option_number: nil,
      suggested_options: [
        {
          "room_type_name" => "Ocean Villa King",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_7_option_1", "check_in" => "2026-05-21" },
            { "position" => 2, "selection_id" => "room_type_7_option_2", "check_in" => "2026-05-22" }
          ]
        },
        {
          "room_type_name" => "Executive Penthouse",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_8_option_1", "check_in" => "2026-05-21" }
          ]
        }
      ],
      suggestion_set_version: 3,
      message: "ocean villa king",
      pending_selection: { "check_in" => "2026-05-21" }
    ).call

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_7_option_1")
  end

  it "selects directly when room type and date are both present in the same message" do
    result = described_class.new(
      option_number: nil,
      suggested_options: [
        {
          "room_type_name" => "Ocean Villa King",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_7_option_1", "check_in" => "2026-05-21" },
            { "position" => 2, "selection_id" => "room_type_7_option_2", "check_in" => "2026-05-22" }
          ]
        },
        {
          "room_type_name" => "Executive Penthouse",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_8_option_1", "check_in" => "2026-05-22" }
          ]
        }
      ],
      suggestion_set_version: 3,
      check_in: "2026-05-22",
      message: "ok i want to book executive on may 22"
    ).call

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_8_option_1")
  end

  it "matches a unique partial room type name using pending date context" do
    result = described_class.new(
      option_number: nil,
      suggested_options: [
        {
          "room_type_name" => "Executive Penthouse",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_8_option_1", "check_in" => "2026-05-21" }
          ]
        },
        {
          "room_type_name" => "Garden Prestige Suite",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_9_option_1", "check_in" => "2026-05-21" },
            { "position" => 2, "selection_id" => "room_type_9_option_2", "check_in" => "2026-05-22" }
          ]
        }
      ],
      suggestion_set_version: 3,
      message: "garden prestige suit",
      pending_selection: { "check_in" => "2026-05-21" }
    ).call

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_9_option_1")
  end

  it "treats executive one as a room type shorthand, not option one" do
    result = described_class.new(
      option_number: nil,
      suggested_options: [
        {
          "room_type_name" => "Executive Penthouse",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_8_option_1", "check_in" => "2026-07-01" },
            { "position" => 2, "selection_id" => "room_type_8_option_2", "check_in" => "2026-07-02" }
          ]
        },
        {
          "room_type_name" => "Garden Prestige Suite",
          "options" => [
            { "position" => 1, "selection_id" => "room_type_9_option_1", "check_in" => "2026-07-01" }
          ]
        }
      ],
      suggestion_set_version: 3,
      message: "executive one"
    ).call

    expect(result["success"]).to be(false)
    expect(result["error"]).to eq("room_type_requires_option_number")
    expect(result["room_type_name"]).to eq("Executive Penthouse")
  end
end
