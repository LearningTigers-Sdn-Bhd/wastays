# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::RadioGroup, type: :component do
  RadioGroupObject = Class.new do
    include ActiveModel::Model
    attr_accessor :board
  end

  def form_for(object = RadioGroupObject.new)
    ActionView::Helpers::FormBuilder.new(:profile, object, vc_test_view_context, {})
  end

  let(:options) do
    [
      { label: "Room only", value: "room_only" },
      { label: "Breakfast", value: "bnb", description: "Daily buffet" },
      { label: "Full board", value: "full", disabled: true }
    ]
  end

  it "renders an accessible radiogroup with a legend, one radio per option, and unique ids" do
    render_inline(
      described_class.new(
        form: form_for, attribute: :board, label: "Board basis",
        description: "Choose one.", options: options, selected: "bnb", required: true
      )
    )

    expect(page).to have_css("fieldset.panel-radio-group[role='radiogroup'][aria-labelledby='profile_board-group-legend'][aria-required='true']")
    expect(page).to have_css("legend#profile_board-group-legend", text: "Board basis")
    expect(page).to have_css(".panel-radio__input", count: 3)
    expect(page).to have_css("input#profile_board_room_only[type='radio'][name='profile[board]'][value='room_only']")
    expect(page).to have_css("input#profile_board_bnb[checked]")
    expect(page).to have_css("input#profile_board_full[disabled]")
    expect(page).to have_css("#profile_board-group-description", text: "Choose one.")
    expect(page).to have_css("legend .panel-radio-group__required", count: 1)
    expect(page).to have_css("input[required]", count: 3)
    expect(page).to have_no_css(".panel-radio__required")
  end

  it "accepts [label, value] pairs and marks the selected option for a name source" do
    render_inline(
      described_class.new(
        name: "board", label: "Board", options: [ [ "Room only", "room_only" ], [ "Full board", "full" ] ],
        selected: "full"
      )
    )

    expect(page).to have_css("input#board_room_only[type='radio'][name='board']:not([checked])")
    expect(page).to have_css("input#board_full[checked]")
  end

  it "surfaces the group error once and does not repeat it on each radio" do
    object = RadioGroupObject.new
    object.errors.add(:board, "must be selected")

    render_inline(described_class.new(form: form_for(object), attribute: :board, label: "Board", options: options))

    expect(page).to have_css("fieldset[aria-invalid='true'][aria-describedby='profile_board-group-error'][data-invalid='true']")
    expect(page).to have_css("#profile_board-group-error.panel-radio-group__error[role='alert']", text: "must be selected")
    expect(page).to have_no_css(".panel-radio__error")
  end

  it "keeps the group hint under the legend alongside the error and references both in aria" do
    object = RadioGroupObject.new
    object.errors.add(:board, "must be selected")

    render_inline(
      described_class.new(form: form_for(object), attribute: :board, label: "Board",
                          description: "Choose one to continue.", options: options)
    )

    expect(page).to have_css("fieldset[aria-describedby='profile_board-group-description profile_board-group-error']")
    expect(page).to have_css("#profile_board-group-description", text: "Choose one to continue.")
    expect(page).to have_css("#profile_board-group-error", text: "must be selected")
  end

  it "rejects missing labels, options, and invalid sources" do
    expect { described_class.new(name: "board", label: nil, options: options) }.to raise_error(ArgumentError, "Radio groups require a label")
    expect { described_class.new(name: "board", label: "Board", options: []) }.to raise_error(ArgumentError, "Radio groups require options")
    expect { described_class.new(form: form_for, label: "Board", options: options) }.to raise_error(ArgumentError, "Radio groups require either form: and attribute:, or name:")
  end
end
