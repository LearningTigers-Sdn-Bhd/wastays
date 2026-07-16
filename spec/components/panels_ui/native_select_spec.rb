# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::NativeSelect, type: :component do
  NativeSelectObject = Class.new do
    include ActiveModel::Model
    attr_accessor :board, :country
  end

  def form_for(object = NativeSelectObject.new)
    ActionView::Helpers::FormBuilder.new(:profile, object, vc_test_view_context, {})
  end

  it "renders a Rails select with choices and passes through HTML, data, and ARIA attributes" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :board,
        choices: [ [ "Room only", "room_only" ], [ "Breakfast", "bnb" ] ],
        described_by: "board-hint",
        class: "w-full",
        data: { controller: "board-check" },
        aria: { describedby: "external-description" }
      )
    )

    select = page.find("select#profile_board")
    expect(select[:class]).to include("panel-native-select", "w-full")
    expect(select["data-controller"]).to eq("board-check")
    expect(select["data-size"]).to eq("md")
    expect(select["aria-describedby"]).to eq("external-description board-hint")
    expect(page).to have_css("select#profile_board option[value='room_only']", text: "Room only")
    expect(page).to have_css("select#profile_board option[value='bnb']", text: "Breakfast")
  end

  it "applies invalid, disabled, and multiple states while defaulting an unknown size" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :board,
        choices: [ [ "Room only", "room_only" ] ],
        size: :bogus,
        invalid: true,
        required: true,
        disabled: true,
        multiple: true
      )
    )

    select = page.find("select#profile_board")
    expect(select["data-size"]).to eq("md")
    expect(select["aria-invalid"]).to eq("true")
    expect(select[:required]).to eq("required")
    expect(select[:disabled]).to eq("disabled")
    expect(select[:multiple]).to eq("multiple")
  end

  it "renders a leading prompt option when nothing is selected" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :board,
        choices: [ [ "Room only", "room_only" ], [ "Breakfast", "bnb" ] ],
        prompt: "Choose a board basis"
      )
    )

    expect(page.all("select#profile_board option").first.text).to eq("Choose a board basis")
  end

  it "marks the selected choice" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :board,
        choices: [ [ "Room only", "room_only" ], [ "Breakfast", "bnb" ] ],
        include_blank: true,
        selected: "bnb"
      )
    )

    expect(page.all("select#profile_board option").first.text).to eq("")
    expect(page.find("select#profile_board option[value='bnb']")[:selected]).to eq("selected")
  end

  it "yields raw option markup when given a block instead of choices" do
    render_inline(described_class.new(form: form_for, attribute: :country)) do
      '<option value="my">Malaysia</option><option value="sg">Singapore</option>'.html_safe
    end

    expect(page).to have_css("select#profile_country option[value='my']", text: "Malaysia")
    expect(page).to have_css("select#profile_country option[value='sg']", text: "Singapore")
  end
end
