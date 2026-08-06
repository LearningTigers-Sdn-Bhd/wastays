# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::DropdownMenu", type: :system do
  before { visit_when_loaded "/system-design?only=dropdown_menu_preview" }

  def open_main_menu
    click_button "Menu options"
    expect(page).to have_css("#sd-dropdown-menu:popover-open")
  end

  def focused_text
    page.evaluate_script("document.activeElement.textContent.trim()")
  end

  it "opens, positions with Floating UI, and focuses the first item" do
    open_main_menu

    expect(focused_text).to eq("Edit booking")
    expect(page.evaluate_script("document.getElementById('sd-dropdown-menu').dataset.placement")).to eq("bottom-start")
    expect(page.evaluate_script("document.getElementById('sd-dropdown-trigger').getAttribute('aria-expanded')")).to eq("true")
  end

  it "supports arrow, Home, End, typeahead, and Escape keyboard behavior" do
    open_main_menu

    dispatch_key("ArrowDown")
    expect(focused_text).to eq("View details")
    dispatch_key("End")
    expect(focused_text).to eq("Export›")
    dispatch_key("Home")
    expect(focused_text).to eq("Edit booking")
    dispatch_key("f")
    expect(focused_text).to eq("Flag for review")
    dispatch_key("Escape")

    expect(page).to have_no_css("#sd-dropdown-menu:popover-open")
    expect(page).to have_css("#sd-dropdown-trigger:focus")
  end

  it "keeps selection menus open and synchronizes native checkbox and radio inputs" do
    open_main_menu

    find("[role='menuitemcheckbox']", text: "Rate").click
    expect(page).to have_css("#sd-dropdown-menu:popover-open")
    expect(find("[role='menuitemcheckbox']", text: "Rate")["aria-checked"]).to eq("true")
    expect(page.evaluate_script("new FormData(document.getElementById('sd-dropdown-form')).getAll('columns[]')")).to contain_exactly("guest", "rate")

    find("[role='menuitemradio']", text: "Compact").click
    expect(find("[role='menuitemradio']", text: "Compact")["aria-checked"]).to eq("true")
    expect(find("[role='menuitemradio']", text: "Comfortable")["aria-checked"]).to eq("false")
    expect(page.evaluate_script("new FormData(document.getElementById('sd-dropdown-form')).get('density')")).to eq("compact")
  end

  it "keeps disabled items focusable but prevents activation" do
    open_main_menu
    disabled = find("[role='menuitem'][aria-disabled='true']", text: "Unavailable action")

    disabled.click

    expect(page).to have_css("#sd-dropdown-menu:popover-open")
    expect(disabled).to be_visible
  end

  it "opens and navigates a collision-aware submenu" do
    open_main_menu
    export = find("[role='menuitem'][aria-haspopup='menu']", text: "Export")
    page.execute_script("arguments[0].focus()", export)
    dispatch_key("ArrowRight")

    expect(page).to have_css("[role='menu'][aria-label='Export']:popover-open")
    expect(page).to have_css("[role='menu'][aria-label='Export'] [role='menuitem']:focus", text: "PDF")
    dispatch_key("ArrowLeft")
    expect(page).to have_no_css("[role='menu'][aria-label='Export']:popover-open")
    expect(page).to have_css("[role='menuitem'][aria-haspopup='menu']:focus", text: "Export")
  end

  it "navigates nested submenus while preserving and recursively closing the ancestor branch" do
    open_main_menu
    export = find("[role='menuitem'][aria-haspopup='menu']", text: "Export")
    page.execute_script("arguments[0].focus()", export)
    dispatch_key("ArrowRight")
    expect(page).to have_css("[role='menu'][aria-label='Export'] [role='menuitem']:focus", text: "PDF")
    statements = find("[role='menuitem'][aria-controls='sd-dropdown-statements']", text: "Statements")
    page.execute_script("arguments[0].focus()", statements)

    expect(focused_text).to eq("Statements›")
    dispatch_key("ArrowRight")
    expect(page).to have_css("[role='menu'][aria-label='Export']:popover-open")
    expect(page).to have_css("#sd-dropdown-statements:popover-open [role='menuitem']:focus", text: "Monthly")

    archives = find("[role='menuitem'][aria-controls='sd-dropdown-archives']", text: "Archives")
    page.execute_script("arguments[0].focus()", archives)
    dispatch_key("ArrowRight")
    expect(page).to have_no_css("#sd-dropdown-statements:popover-open")
    expect(page).to have_css("[role='menu'][aria-label='Export']:popover-open")
    expect(page).to have_css("#sd-dropdown-archives:popover-open [role='menuitem']:focus", text: "ZIP")

    dispatch_key("ArrowLeft")
    expect(page).to have_no_css("#sd-dropdown-archives:popover-open")
    expect(page).to have_css("[role='menuitem'][aria-controls='sd-dropdown-archives']:focus", text: "Archives")
    dispatch_key("ArrowLeft")
    expect(page).to have_no_css("[role='menu'][aria-label='Export']:popover-open")
    expect(page).to have_css("#sd-dropdown-menu:popover-open [role='menuitem']:focus", text: "Export")

    dispatch_key("ArrowRight")
    expect(page).to have_css("[role='menu'][aria-label='Export'] [role='menuitem']:focus", text: "PDF")
    statements = find("[role='menuitem'][aria-controls='sd-dropdown-statements']", text: "Statements")
    page.execute_script("arguments[0].focus()", statements)
    dispatch_key("ArrowRight")
    expect(page).to have_css("#sd-dropdown-statements [role='menuitem']:focus", text: "Monthly")
    find("h1", text: "PanelsUI").click
    expect(page).to have_no_css("#sd-dropdown-menu:popover-open, [role='menu'][aria-label='Export']:popover-open, #sd-dropdown-statements:popover-open")
  end

  it "opens each nested submenu level with pointer clicks" do
    open_main_menu

    find("[role='menuitem'][aria-controls]", text: "Export").click
    expect(page).to have_css("[role='menu'][aria-label='Export']:popover-open")
    find("[role='menuitem'][aria-controls='sd-dropdown-statements']", text: "Statements").click
    expect(page).to have_css("#sd-dropdown-statements:popover-open", text: "Monthly")
  end

  it "flips away from a constrained viewport edge and closes on outside pointer input" do
    page.execute_script(<<~JS)
      const root = document.getElementById("sd-dropdown")
      Object.assign(root.style, { position: "fixed", left: "8px", bottom: "0" })
    JS
    open_main_menu

    expect(page).to have_css("#sd-dropdown-menu[data-placement^='top']")
    find("h1", text: "PanelsUI").click
    expect(page).to have_no_css("#sd-dropdown-menu:popover-open")
  end
end
