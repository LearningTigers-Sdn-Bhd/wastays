# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::SelectMenu", type: :system do
  # The light "Board basis" field from the SelectMenu showcase preview.
  TRIGGER = "select_menu_panel_light_board-trigger"
  LISTBOX = "select_menu_panel_light_board-listbox"
  NATIVE = "select_menu_panel_light_board"
  ROOM_TRIGGER = "select_menu_panel_light_room_type-trigger"
  ROOM_LISTBOX = "select_menu_panel_light_room_type-listbox"
  ROOM_NATIVE = "select_menu_panel_light_room_type"

  before { visit_when_loaded "/system-design?only=select_menu_preview" }

  def open_menu
    find_by_id(TRIGGER).click
    expect(page).to have_css("##{LISTBOX}:popover-open")
  end

  def focused_text
    page.evaluate_script("document.activeElement.textContent.trim()")
  end

  def send_key(key)
    page.execute_script(<<~JS)
      document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: #{key.to_json}, bubbles: true }))
    JS
  end

  def native_value
    page.evaluate_script("document.getElementById('#{NATIVE}').value")
  end

  it "enhances the field: hides the native select and shows the styled trigger" do
    expect(page).to have_css("##{TRIGGER}", visible: true)
    expect(find_by_id(NATIVE, visible: :all)["aria-hidden"]).to eq("true")
    expect(find_by_id(TRIGGER)["aria-haspopup"]).to eq("listbox")
    # Nothing selected yet — the trigger shows the placeholder.
    expect(find("##{TRIGGER} .panel-select-menu__value")["data-placeholder"]).to eq("true")
  end

  it "opens, positions with Floating UI, and focuses the first option" do
    open_menu

    expect(focused_text).to eq("Room only")
    expect(page.evaluate_script("document.getElementById('#{LISTBOX}').dataset.placement")).to start_with("bottom")
    expect(find_by_id(TRIGGER)["aria-expanded"]).to eq("true")
  end

  it "supports arrow, Home, End, and typeahead navigation" do
    open_menu

    send_key("ArrowDown")
    expect(focused_text).to eq("Breakfast included")
    send_key("End")
    expect(focused_text).to eq("Full board")
    send_key("Home")
    expect(focused_text).to eq("Room only")
    send_key("b")
    expect(focused_text).to eq("Breakfast included")
  end

  it "selects an option, mirrors it to the native select, closes, and restores focus" do
    open_menu

    find("[role='option']", text: "Full board").click

    expect(page).to have_no_css("##{LISTBOX}:popover-open")
    expect(native_value).to eq("full")
    expect(find("##{TRIGGER} .panel-select-menu__value")).to have_text("Full board")
    expect(find("##{TRIGGER} .panel-select-menu__value")["data-placeholder"]).to eq("false")
    expect(page.evaluate_script("document.activeElement.id")).to eq(TRIGGER)
    expect(find("##{LISTBOX} [role='option'][data-value='full']", visible: :all)["aria-selected"]).to eq("true")
  end

  it "restores the enhanced UI when its form resets" do
    open_menu
    find("[role='option']", text: "Full board").click
    find_by_id(ROOM_TRIGGER).click
    expect(page).to have_css("##{ROOM_LISTBOX}:popover-open")
    find("##{ROOM_LISTBOX} [role='option']", text: "Suite").click

    find(:xpath, "//select[@id='#{NATIVE}']/ancestor::form", visible: :all).click_button("Reset selects")

    expect(native_value).to eq("")
    label = find("##{TRIGGER} .panel-select-menu__value")
    expect(label).to have_text("Select a board basis")
    expect(label["data-placeholder"]).to eq("true")
    expect(find("##{LISTBOX} [role='option'][data-value='full']", visible: :all)["aria-selected"]).to eq("false")

    expect(page.evaluate_script("document.getElementById('#{ROOM_NATIVE}').value")).to eq("dlx_twin")
    expect(find("##{ROOM_TRIGGER} .panel-select-menu__value")).to have_text("Deluxe Twin")
    expect(find("##{ROOM_LISTBOX} [role='option'][data-value='dlx_twin']", visible: :all)["aria-selected"]).to eq("true")
  end

  it "replaces dynamic choices in both the native select and styled listbox" do
    page.execute_script(<<~JS)
      const root = document.getElementById('#{NATIVE}-select-menu')
      const controller = window.Stimulus.getControllerForElementAndIdentifier(root, 'panels-ui--select-menu')
      controller.replaceOptions([
        { label: 'Advance purchase', value: 'advance' },
        { label: 'Corporate (unavailable)', value: 'corporate', disabled: true }
      ], 'advance')
    JS

    expect(page.evaluate_script("[...document.getElementById('#{NATIVE}').options].map(option => [option.text, option.value, option.disabled])")).to eq([
      [ "Advance purchase", "advance", false ],
      [ "Corporate (unavailable)", "corporate", true ]
    ])
    expect(native_value).to eq("advance")
    expect(find("##{TRIGGER} .panel-select-menu__value")).to have_text("Advance purchase")
    expect(page).to have_css("##{LISTBOX} [role='option']", count: 2, visible: :all)
    expect(find("##{LISTBOX} [data-value='corporate']", visible: :all)["aria-disabled"]).to eq("true")
  end

  it "skips disabled options and closes on Escape and outside pointer input" do
    open_menu
    disabled = find("[role='option'][aria-disabled='true']", text: "All inclusive (sold out)")
    disabled.click

    expect(page).to have_css("##{LISTBOX}:popover-open")
    expect(native_value).not_to eq("all_in")

    send_key("Escape")
    expect(page).to have_no_css("##{LISTBOX}:popover-open")
    expect(page.evaluate_script("document.activeElement.id")).to eq(TRIGGER)
  end
end
