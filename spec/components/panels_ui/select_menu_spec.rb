# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::SelectMenu, type: :component do
  SelectMenuObject = Class.new do
    include ActiveModel::Model
    attr_accessor :board
  end

  def form_for(object = SelectMenuObject.new)
    ActionView::Helpers::FormBuilder.new(:profile, object, vc_test_view_context, {})
  end

  let(:choices) do
    [
      { label: "Room only", value: "room_only" },
      { label: "Breakfast included", value: "bnb" },
      { label: "Full board", value: "full", disabled: true }
    ]
  end

  it "renders the native select as the source of truth alongside the styled trigger and listbox" do
    render_inline(described_class.new(form: form_for, attribute: :board, choices: choices, prompt: "Pick one"))

    # Native control still present and submittable.
    expect(page).to have_css("select#profile_board.panel-native-select.panel-select-menu__native")
    expect(page).to have_css("select#profile_board[data-panels-ui--select-menu-target='native']")

    # Enhancement controller wired on the root.
    root = page.find(".panel-select-menu")
    expect(root["data-controller"]).to include("panels-ui--select-menu")
    expect(root["data-panels-ui--select-menu-placeholder-value"]).to eq("Pick one")

    # Trigger exposes listbox combobox semantics and shows the placeholder.
    trigger = page.find("button#profile_board-trigger")
    expect(trigger["aria-haspopup"]).to eq("listbox")
    expect(trigger["aria-expanded"]).to eq("false")
    expect(trigger["aria-controls"]).to eq("profile_board-listbox")
    expect(page.find(".panel-select-menu__value")["data-placeholder"]).to eq("true")
    expect(page.find(".panel-select-menu__value")).to have_text("Pick one")
  end

  it "mirrors each choice as a role=option with selection and disabled state" do
    render_inline(described_class.new(form: form_for, attribute: :board, choices: choices, selected: "bnb"))

    options = page.all(".panel-select-menu__listbox [role='option']")
    expect(options.map(&:text).map(&:strip)).to eq([ "Room only", "Breakfast included", "Full board" ])

    expect(page.find("[role='option'][data-value='bnb']")["aria-selected"]).to eq("true")
    expect(page.find("[role='option'][data-value='room_only']")["aria-selected"]).to eq("false")
    expect(page.find("[role='option'][data-value='full']")["aria-disabled"]).to eq("true")

    # A pre-selected value pre-fills the trigger label (no flash before JS).
    label = page.find(".panel-select-menu__value")
    expect(label).to have_text("Breakfast included")
    expect(label["data-placeholder"]).to eq("false")
  end

  it "reflects invalid and disabled states onto the root and trigger" do
    render_inline(
      described_class.new(form: form_for, attribute: :board, choices: choices, invalid: true, disabled: true)
    )

    root = page.find(".panel-select-menu")
    expect(root["data-invalid"]).to eq("true")
    expect(root["data-disabled"]).to eq("true")

    trigger = page.find("button#profile_board-trigger")
    expect(trigger[:disabled]).to eq("disabled")
    expect(trigger["aria-invalid"]).to eq("true")
    expect(page.find("select#profile_board")[:disabled]).to eq("disabled")
  end

  it "accepts plain [label, value] pairs and threads described_by to the trigger" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :board,
        choices: [ [ "Room only", "room_only" ], [ "Breakfast", "bnb" ] ],
        described_by: "board-hint"
      )
    )

    expect(page.all(".panel-select-menu__listbox [role='option']").size).to eq(2)
    expect(page.find("button#profile_board-trigger")["aria-describedby"]).to eq("board-hint")
  end

  it "raises without choices" do
    expect {
      described_class.new(form: form_for, attribute: :board, choices: [])
    }.to raise_error(ArgumentError, /require choices/)
  end
end
