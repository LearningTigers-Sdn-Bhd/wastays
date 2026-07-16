# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Radio, type: :component do
  RadioObject = Class.new do
    include ActiveModel::Model
    attr_accessor :board
  end

  def form_for(object = RadioObject.new)
    ActionView::Helpers::FormBuilder.new(:profile, object, vc_test_view_context, {})
  end

  it "renders a builder radio whose id folds in the value and emits no hidden field" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :board,
        value: "full",
        label: "Full board",
        description: "Breakfast, lunch, and dinner.",
        checked: true
      )
    )

    expect(page).to have_css("label.panel-radio[for='profile_board_full'][data-size='md'][data-variant='default']", text: "Full board")
    expect(page).to have_css("input#profile_board_full[type='radio'][name='profile[board]'][value='full'][checked]")
    expect(page).to have_css("#profile_board_full-description.panel-radio__description", text: "Breakfast, lunch, and dinner.")
    expect(page).to have_no_css("input[type='hidden']", visible: :all)
  end

  it "renders a standalone card radio with custom attributes" do
    render_inline(
      described_class.new(
        name: "board",
        value: "room_only",
        label: "Room only",
        variant: :card,
        size: :lg,
        disabled: true,
        class: "w-full"
      )
    )

    expect(page).to have_css("label.panel-radio[data-variant='card'][data-size='lg'][data-disabled='true'][for='board_room_only']")
    expect(page).to have_css("input#board_room_only.panel-radio__input.w-full[type='radio'][name='board'][value='room_only'][disabled]")
  end

  it "rejects missing labels and invalid control sources" do
    expect { described_class.new(name: "board", value: "x", label: nil) }.to raise_error(ArgumentError, "Radio buttons require a label")
    expect { described_class.new(form: form_for, label: "Board") }.to raise_error(ArgumentError, "Radio buttons require either form: and attribute:, or name:")
  end
end
