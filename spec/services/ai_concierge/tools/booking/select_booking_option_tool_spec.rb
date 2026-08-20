require "rails_helper"

RSpec.describe AiConcierge::Tools::Booking::SelectBookingOptionTool do
  # The catalogue is numbered in one run across room types, which is what makes
  # a position enough on its own.
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
          { "position" => 3, "selection_id" => "room_type_2_option_1", "check_in" => "2026-08-01" },
          { "position" => 4, "selection_id" => "room_type_2_option_2", "check_in" => "2026-08-03" }
        ]
      }
    ]
  end

  def select(message, **slots)
    described_class.new(
      option_number: nil,
      suggested_options: suggested_options,
      suggestion_set_version: 3,
      **slots,
      message: message
    ).call
  end

  it "selects on the number alone" do
    result = select("3")

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_2_option_1")
    expect(result.dig("selected_option", "room_type_name")).to eq("Deluxe Room")
    expect(result["suggestion_set_version"]).to eq(3)
  end

  # The catalogue asks for a number, and guests send one wrapped in whatever
  # words they would have used out loud.
  it "reads the number out of the shapes guests actually write it in" do
    {
      "2" => "room_type_1_option_2",
      "no 2" => "room_type_1_option_2",
      "no.2" => "room_type_1_option_2",
      "option 2" => "room_type_1_option_2",
      "2nd" => "room_type_1_option_2",
      "the second one" => "room_type_1_option_2",
      "2 please" => "room_type_1_option_2",
      "i'll take 2" => "room_type_1_option_2",
      "option one" => "room_type_1_option_1",
      "just 1" => "room_type_1_option_1",
      "option 4" => "room_type_2_option_2"
    }.each do |answer, selection_id|
      result = select(answer)

      expect(result["success"]).to be(true), "expected #{answer.inspect} to select an option"
      expect(result.dig("selected_option", "selection_id")).to eq(selection_id)
    end
  end

  # A number that counts something else is not an answer to the list.
  it "leaves a number that counts something other than rows alone" do
    [ "2 nights", "2 rooms", "2 adults", "august 3rd" ].each do |answer|
      expect(select(answer)["success"]).to be(false), "expected #{answer.inspect} not to select an option"
    end
  end

  it "takes the number the guest wrote over the one the model passed" do
    result = described_class.new(
      option_number: 4,
      suggested_options: suggested_options,
      suggestion_set_version: 3,
      message: "option 1"
    ).call

    expect(result.dig("selected_option", "selection_id")).to eq("room_type_1_option_1")
  end

  it "falls back to the number the model passed when the message carries none" do
    result = described_class.new(
      option_number: 4,
      suggested_options: suggested_options,
      suggestion_set_version: 3,
      message: "yes please"
    ).call

    expect(result.dig("selected_option", "selection_id")).to eq("room_type_2_option_2")
  end

  it "resumes a saved selection by its selection id" do
    result = select("", selection_id: "room_type_2_option_1")

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_2_option_1")
  end

  it "ignores a selection id no option has and reads the number instead" do
    result = select("option 1", selection_id: "opt_1")

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_1_option_1")
  end

  # The room name is no longer a way into the list: it only ever guessed, and
  # the number already names exactly one row. Saying so is the honest answer.
  it "does not select on a room type name" do
    [ "Garden Prestige Suite", "garden prestige", "i want to book at garden prestige" ].each do |answer|
      result = select(answer)

      expect(result["success"]).to be(false), "expected #{answer.inspect} not to select an option"
      expect(result["error"]).to eq("invalid_selection")
    end
  end

  it "reads the number even when the guest also names a room" do
    result = select("garden prestige option 4")

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_2_option_2")
  end

  it "cannot match a message that names nothing on the list" do
    result = select("the treehouse")

    expect(result["success"]).to be(false)
    expect(result["error"]).to eq("invalid_selection")
  end

  it "cannot match a number the list does not have" do
    expect(select("option 9")["success"]).to be(false)
  end

  # Threads already in flight carry the older per-room-type numbering, where a
  # position repeats. Nothing can be read from it, and the guest is asked again
  # rather than sent a room they did not pick.
  it "refuses a repeated position from a catalogue numbered the old way" do
    legacy_options = suggested_options.map do |group|
      group.merge("options" => group["options"].each_with_index.map { |option, index| option.merge("position" => index + 1) })
    end

    result = described_class.new(
      option_number: nil,
      suggested_options: legacy_options,
      suggestion_set_version: 3,
      message: "option 2"
    ).call

    expect(result["success"]).to be(false)
    expect(result["error"]).to eq("invalid_selection")
  end

  # A list with one row on it has only one answer, whatever words arrive.
  it "selects the only option when the catalogue has a single row" do
    result = described_class.new(
      option_number: nil,
      suggested_options: [ suggested_options.first.merge("options" => [ suggested_options.first["options"].first ]) ],
      suggestion_set_version: 3,
      message: "sounds good"
    ).call

    expect(result["success"]).to be(true)
    expect(result.dig("selected_option", "selection_id")).to eq("room_type_1_option_1")
  end
end
