# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::MultiSelect", type: :system do
  MULTISELECT_NATIVE = "multi_select_panel_light_destination"
  MULTISELECT_ROOT = "#{MULTISELECT_NATIVE}-multi-select"

  before { visit_when_loaded "/system-design?only=multi_select_preview" }

  def root
    find_by_id(MULTISELECT_ROOT)
  end

  # The dropdown_input plugin moves the search field into the menu; it is the
  # control input, so it carries the combobox role and the copied aria attributes.
  def search_input
    root.find(".ts-dropdown input.dropdown-input", visible: :all)
  end

  # A native <select multiple>'s `.value` exposes only the first selection, so read
  # the full set of selected option values instead.
  def selected_values
    page.evaluate_script(
      "Array.from(document.getElementById('#{MULTISELECT_NATIVE}').selectedOptions).map(o => o.value)"
    )
  end

  # A user opens the control by clicking the trigger, not the (in-menu) search.
  def open_multi_select
    root.find(".ts-control").click
    expect(root).to have_css(".ts-wrapper.dropdown-active")
  end

  it "enhances the native multiple select and moves the search field into the menu" do
    expect(root["data-enhanced"]).to eq("true")
    expect(root).to have_css(".ts-wrapper.multi.plugin-dropdown_input.plugin-remove_button")
    expect(root).to have_css(".ts-dropdown .dropdown-input-wrap input.dropdown-input", visible: :all)

    native = find_by_id(MULTISELECT_NATIVE, visible: :all)
    expect(native).to match_css(".panel-combobox__native")
    expect(native[:multiple]).to be_truthy

    # Tom Select repoints the field label at its generated control, and the
    # controller copies the field's description id onto the search input.
    expect(page).to have_css("label[for='#{MULTISELECT_NATIVE}-ts-control']", visible: :all)
    expect(search_input["aria-describedby"]).to eq("#{MULTISELECT_NATIVE}-hint")
  end

  it "selects several options into the native select as removable pills" do
    open_multi_select
    root.find(".ts-dropdown .option", text: "Berlin, Germany").click
    # closeAfterSelect is off, so the menu stays open for the next pick.
    root.find(".ts-dropdown .option", text: "Tokyo, Japan").click

    expect(selected_values).to contain_exactly("berlin", "tokyo")
    expect(root).to have_css(".ts-control .item", text: "Berlin, Germany")
    expect(root).to have_css(".ts-control .item", text: "Tokyo, Japan")
    expect(root).to have_css(".ts-control .item", count: 2)
  end

  it "removes a selection via the pill's remove button" do
    open_multi_select
    root.find(".ts-dropdown .option", text: "Berlin, Germany").click
    root.find(".ts-dropdown .option", text: "Tokyo, Japan").click
    expect(selected_values).to contain_exactly("berlin", "tokyo")

    root.find(".ts-control .item", text: "Berlin, Germany").find(".remove").click

    expect(selected_values).to eq([ "tokyo" ])
    expect(root).to have_css(".ts-control .item", count: 1)
    expect(root).to have_no_css(".ts-control .item", text: "Berlin, Germany")
  end

  it "shows the placeholder in the empty trigger and hides it once an item is selected" do
    placeholder = root.find(".ts-control input.items-placeholder", visible: :all)
    expect(placeholder[:placeholder]).to eq("Search destinations")
    # Visible (non-zero width) while empty — regression guard for the collapsed
    # placeholder that hid the prompt.
    expect(page.evaluate_script(
      "document.querySelector('##{MULTISELECT_ROOT} .ts-control input.items-placeholder').offsetWidth > 0"
    )).to be(true)

    open_multi_select
    root.find(".ts-dropdown .option", text: "Berlin, Germany").click

    expect(root).to have_css(".ts-wrapper.has-items")
    expect(page.evaluate_script(
      "getComputedStyle(document.querySelector('##{MULTISELECT_ROOT} .ts-control input.items-placeholder')).display"
    )).to eq("none")
  end

  it "caps the trigger at three pills and collapses the rest into a +N more badge" do
    open_multi_select
    [ "Bangkok, Thailand", "Berlin, Germany", "London, United Kingdom", "Tokyo, Japan" ].each do |label|
      root.find(".ts-dropdown .option", text: label).click
    end

    # All four are selected, but only the first three pills show in the trigger.
    expect(root).to have_css(".ts-control > .item", count: 3)
    expect(root).to have_css(".ts-control > .item", count: 4, visible: :all)
    expect(root).to have_css(".ts-control .panel-multi-select__more", text: "+1 more")
  end

  it "removes the exact value even when the +N more overflow badge is present" do
    # Regression: the overflow badge used to be injected *between* the pills in the
    # control. Tom Select maps a pill to its `items` entry by its position among the
    # control's children, so a foreign node there desynced the mapping and removeItem
    # deleted a neighbouring value. The badge now sits after the trailing input.
    amenities = find_by_id("multi_select_panel_light_amenities-multi-select")
    # 4 of 5 preselected → the overflow badge is already showing.
    amenities.find(".panel-multi-select__more").click
    amenities.find(".ts-dropdown .option", text: "Gym").click
    expect(amenities).to have_css(".ts-control .panel-multi-select__more")

    amenities.find(".ts-dropdown .panel-multi-select__selected .panel-multi-select__badge", text: "Parking")
             .find(".panel-multi-select__badge-remove").click

    selected = page.evaluate_script(
      "Array.from(document.getElementById('multi_select_panel_light_amenities').selectedOptions).map(o => o.value)"
    )
    expect(selected).to contain_exactly("wifi", "pool", "breakfast", "gym")
    expect(amenities).to have_css(".ts-dropdown-content .option", text: "Parking")
  end

  it "lists every selection as a removable badge in the dropdown panel" do
    open_multi_select
    root.find(".ts-dropdown .option", text: "Berlin, Germany").click
    root.find(".ts-dropdown .option", text: "Tokyo, Japan").click

    panel = root.find(".ts-dropdown .panel-multi-select__selected")
    expect(panel).to have_css(".panel-multi-select__badge", count: 2)
    expect(panel).to have_css(".panel-multi-select__badge", text: "Berlin, Germany")

    panel.find(".panel-multi-select__badge", text: "Berlin, Germany").find(".panel-multi-select__badge-remove").click

    expect(selected_values).to eq([ "tokyo" ])
    expect(panel).to have_css(".panel-multi-select__badge", count: 1)
    expect(root).to have_no_css(".ts-control .item", text: "Berlin, Germany")
  end

  it "shows an empty-menu message once every option is selected" do
    amenities = find_by_id("multi_select_panel_light_amenities-multi-select")
    # 4 of 5 options are preselected; open via the "+N more" summary badge (a
    # center click on a filled trigger lands on a pill under the headless driver).
    amenities.find(".panel-multi-select__more").click
    expect(amenities).to have_css(".ts-wrapper.dropdown-active")
    # Add the last remaining option.
    amenities.find(".ts-dropdown .option", text: "Gym").click

    expect(amenities).to have_css(".ts-dropdown .panel-multi-select__all-selected", text: "All options selected")
    expect(amenities).to have_no_css(".ts-dropdown-content .option")

    # Freeing an option hides the message again.
    amenities.find(".ts-dropdown .panel-multi-select__selected .panel-multi-select__badge", text: "Gym")
             .find(".panel-multi-select__badge-remove").click
    expect(amenities).to have_no_css(".ts-dropdown .panel-multi-select__all-selected")
    expect(amenities).to have_css(".ts-dropdown-content .option", text: "Gym")
  end

  it "shows the overridden empty text when the filter matches nothing" do
    open_multi_select
    search_input.send_keys("zzzzz")

    expect(root).to have_css(".ts-dropdown .panel-combobox__empty", text: "No destinations match your search.")
    expect(root).to have_no_css(".ts-dropdown .option")
  end

  it "does not allow selecting disabled options" do
    open_multi_select
    root.find(".ts-dropdown .option", text: "Kuching", visible: :all).click

    expect(selected_values).to be_empty
    expect(root).to have_no_css(".ts-control .item")
  end

  it "resynchronizes after a form reset" do
    open_multi_select
    root.find(".ts-dropdown .option", text: "Berlin, Germany").click
    root.find(".ts-dropdown .option", text: "Tokyo, Japan").click
    expect(selected_values).to contain_exactly("berlin", "tokyo")

    # The menu stays open after selecting (closeAfterSelect is off); close it so it
    # can't overlap the reset button.
    search_input.send_keys(:escape)
    expect(root).to have_no_css(".ts-wrapper.dropdown-active")

    root.ancestor("form").find("button[type='reset']").click
    expect(selected_values).to be_empty
    expect(root).to have_no_css(".ts-control .item")
  end

  it "does not duplicate the Tom Select wrapper after Turbo reconnects" do
    page.execute_script("Turbo.visit('/system-design?only=multi_select_preview')")
    expect(page).to have_css("##{MULTISELECT_ROOT}[data-enhanced='true']")
    expect(root).to have_css(".ts-wrapper", count: 1)
  end

  # Same reliable formulation as the combobox spec: open via .ts-control, then
  # send_keys into the in-menu search input and let have_css waiting settle on the
  # filtered result.
  it "filters options as the user types" do
    open_multi_select
    search_input.send_keys("Berl")

    expect(root).to have_css(".ts-dropdown .option", text: "Berlin, Germany")
    expect(root).to have_css(".ts-dropdown .option", count: 1)
    expect(root).to have_no_css(".ts-dropdown .option", text: "Bangkok, Thailand")
  end
end
