# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Combobox", type: :system do
  COMBOBOX_NATIVE = "combobox_panel_light_destination"
  COMBOBOX_ROOT = "#{COMBOBOX_NATIVE}-combobox"

  before { visit_when_loaded "/system-design?only=combobox_preview" }

  def root
    find_by_id(COMBOBOX_ROOT)
  end

  # The dropdown_input plugin moves the search field into the menu; it is the
  # control input, so it carries the combobox role and the copied aria attributes.
  def search_input
    root.find(".ts-dropdown input.dropdown-input", visible: :all)
  end

  def native_value
    page.evaluate_script("document.getElementById('#{COMBOBOX_NATIVE}').value")
  end

  # A user opens the combobox by clicking the trigger, not the (in-menu) search.
  def open_combobox
    root.find(".ts-control").click
    expect(root).to have_css(".ts-wrapper.dropdown-active")
  end

  it "enhances the native select and moves the search field into the menu" do
    expect(root["data-enhanced"]).to eq("true")
    expect(root).to have_css(".ts-wrapper.single.plugin-dropdown_input")
    expect(root).to have_css(".ts-dropdown .dropdown-input-wrap input.dropdown-input", visible: :all)
    expect(find_by_id(COMBOBOX_NATIVE, visible: :all)).to match_css(".panel-combobox__native")

    # Tom Select repoints the field label at its generated control, and the
    # controller copies the field's description id onto the search input.
    expect(page).to have_css("label[for='#{COMBOBOX_NATIVE}-ts-control']", visible: :all)
    expect(search_input["aria-describedby"]).to eq("#{COMBOBOX_NATIVE}-hint")
  end

  it "selects an option into the native select and reflects it in the trigger" do
    open_combobox
    root.find(".ts-dropdown .option", text: "Berlin, Germany").click

    expect(native_value).to eq("berlin")
    expect(root).to have_no_css(".ts-wrapper.dropdown-active")
    expect(root).to have_css(".ts-control .item", text: "Berlin, Germany")
  end

  it "does not allow selecting disabled options" do
    open_combobox
    root.find(".ts-dropdown .option", text: "Kuching", visible: :all).click

    expect(native_value).to eq("")
    expect(root).to have_no_css(".ts-control .item")
  end

  it "resynchronizes after a form reset" do
    open_combobox
    root.find(".ts-dropdown .option", text: "Berlin, Germany").click
    expect(native_value).to eq("berlin")

    root.ancestor("form").find("button[type='reset']").click
    expect(native_value).to eq("")
    expect(root).to have_no_css(".ts-control .item")
  end

  it "does not duplicate the Tom Select wrapper after Turbo reconnects" do
    page.execute_script("Turbo.visit('/system-design?only=combobox_preview')")
    expect(page).to have_css("##{COMBOBOX_ROOT}[data-enhanced='true']")
    expect(root).to have_css(".ts-wrapper", count: 1)
  end

  # Type-to-filter is reliable in headless Cuprite/Ferrum *if* we open via
  # .ts-control first, then send_keys into the in-menu search input, and let
  # Capybara's have_css waiting settle on the filtered result. Earlier attempts
  # that drove the field with .set / page.send_keys / JS input events were flaky;
  # this formulation is not (verified over 40 consecutive runs).
  it "filters options as the user types" do
    open_combobox
    search_input.send_keys("Berl")

    expect(root).to have_css(".ts-dropdown .option", text: "Berlin, Germany")
    expect(root).to have_css(".ts-dropdown .option", count: 1)
    expect(root).to have_no_css(".ts-dropdown .option", text: "Bangkok, Thailand")
  end

  # The menu is anchored by floating-ui rather than CSS, because these render
  # inside Sheets where the old absolute anchoring could not see the viewport: a
  # long list ran off the bottom, and nothing constrained the menu's width.
  it "anchors the menu to the control, capped and inside the viewport" do
    open_combobox

    geometry = page.evaluate_script(<<~JS)
      (() => {
        const root = document.getElementById('#{COMBOBOX_ROOT}')
        const menu = root.querySelector('.ts-dropdown')
        const content = root.querySelector('.ts-dropdown-content')
        const menuRect = menu.getBoundingClientRect()
        const controlRect = root.querySelector('.ts-control').getBoundingClientRect()
        return {
          placement: menu.dataset.placement,
          position: getComputedStyle(menu).position,
          widthDelta: Math.abs(menuRect.width - controlRect.width),
          maxHeight: parseInt(content.style.maxHeight, 10),
          withinViewport: menuRect.top >= -1 && menuRect.bottom <= window.innerHeight + 1
        }
      })()
    JS

    expect(geometry["position"]).to eq("fixed")
    expect(geometry["placement"]).to start_with("bottom")
    # Tracks the control's width instead of shrink-to-fitting to its content
    # (which let a multi-select's pills panel stretch it across the viewport).
    # Tolerance is for sub-pixel rounding, not a real difference.
    expect(geometry["widthDelta"]).to be <= 2
    # Capped at the design ceiling rather than growing to fill a tall viewport.
    expect(geometry["maxHeight"]).to be <= 320
    expect(geometry["withinViewport"]).to be true
  end
end
