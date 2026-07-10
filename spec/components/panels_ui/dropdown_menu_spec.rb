# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::DropdownMenu, type: :component do
  def render_menu(placement: :bottom_start, class_name: nil)
    render_inline(described_class.new(id: "actions", placement: placement, class: class_name)) do |menu|
      menu.with_trigger(variant: :secondary, size: :sm, class: "btn") { "Actions" }
      menu.with_item(href: "/edit", variant: :primary) { "Edit" }
      menu.with_checkbox(name: "columns[]", value: "rates", checked: true) { "Rates" }
      menu.with_radio_group(name: "sort", label: "Sort by") do |group|
        group.with_option(value: "date", checked: true) { "Date" }
        group.with_option(value: "name") { "Name" }
      end
      menu.with_separator
      menu.with_group(label: "Danger zone") do |group|
        group.with_item(variant: :danger, disabled: true) { "Delete" }
      end
      menu.with_submenu(label: "Export") do |submenu|
        submenu.with_item(href: "/export.pdf") { "PDF" }
      end
    end
  end

  it "wires the trigger and menu accessibility contract" do
    render_menu

    expect(page).to have_css("#actions[data-controller='panels-ui--dropdown-menu']")
    expect(page).to have_button("Actions")
    expect(page).to have_css("button#actions-trigger.panel-button[aria-haspopup='menu'][aria-expanded='false'][aria-controls='actions-menu'][data-variant='secondary'][data-size='sm']")
    expect(page).to have_css("#actions-menu[role='menu'][popover='manual'][aria-labelledby='actions-trigger']")
  end

  it "renders command, checkbox, and radio items with native form inputs" do
    render_menu

    expect(page).to have_css("a[href='/edit'][role='menuitem'][data-variant='primary']", text: "Edit")
    expect(page).to have_css("[role='menuitemcheckbox'][aria-checked='true']", text: "Rates")
    expect(page).to have_css("input[type='checkbox'][name='columns[]'][value='rates'][checked][hidden]", visible: :all)
    expect(page).to have_css("[role='group'][aria-label='Sort by']")
    expect(page).to have_css("[role='menuitemradio'][aria-checked='true']", text: "Date")
    expect(page).to have_css("input[type='radio'][name='sort'][value='date'][checked][hidden]", visible: :all)
  end

  it "renders separators, labelled groups, disabled semantics, and a one-level submenu" do
    render_menu

    expect(page).to have_css("[role='separator'][aria-orientation='horizontal']")
    expect(page).to have_css("[role='group'][aria-label='Danger zone']")
    expect(page).to have_css("[role='menuitem'][aria-disabled='true'][data-variant='danger']", text: "Delete")
    expect(page).to have_css("[role='menuitem'][aria-haspopup='menu'][aria-expanded='false']", text: "Export")
    expect(page).to have_css("[role='menu'][popover='manual'][aria-label='Export'] a[href='/export.pdf']", text: "PDF", visible: :all)
  end

  it "normalizes placement for Floating UI and merges menu classes" do
    render_menu(placement: :top_end, class_name: "w-72")

    expect(page).to have_css("#actions[data-panels-ui--dropdown-menu-placement-value='top-end']")
    expect(page.find("#actions-menu", visible: :all)[:class]).to include("w-72")
  end

  it "falls back to bottom-start and default item styling for unknown variants" do
    render_inline(described_class.new(id: "fallback", placement: :unknown)) do |menu|
      menu.with_trigger { "Open" }
      menu.with_item(variant: :unknown) { "Item" }
    end

    expect(page).to have_css("#fallback[data-panels-ui--dropdown-menu-placement-value='bottom-start']")
    expect(page).to have_css("#fallback-trigger[data-variant='primary'][data-size='md']", text: "Open")
    expect(page).to have_css("[role='menuitem'][data-variant='default']", text: "Item", visible: :all)
  end
end
