# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::CommandPalette, type: :component do
  def render_palette(**opts)
    render_inline(described_class.new(**{ endpoint: "/hotel/1/global_search" }.merge(opts)))
  end

  describe "root + controller wiring" do
    before { render_palette }

    it "renders the palette root with the Stimulus controller and endpoint value" do
      expect(page).to have_css(
        ".panel-command-palette[data-controller='panels-ui--command-palette']" \
        "[data-panels-ui--command-palette-endpoint-value='/hotel/1/global_search']"
      )
    end

    it "nests the dialog controller on the native <dialog>, distinct from the palette root" do
      expect(page).to have_css("dialog[data-controller='panels-ui--dialog'][data-panels-ui--command-palette-target='dialog']")
    end

    it "wires both controllers to the dialog's native close event and reuses the dialog dismissal actions" do
      action = page.find("dialog")["data-action"]
      expect(action).to include("close->panels-ui--dialog#onClose")
      expect(action).to include("close->panels-ui--command-palette#reset")
      expect(action).to include("cancel->panels-ui--dialog#onCancel")
      expect(action).to include("click->panels-ui--dialog#backdropClose")
    end
  end

  describe "navbar trigger" do
    before { render_palette(placeholder: "Search dashboard pages...") }

    it "renders the wide pill trigger that opens the palette" do
      expect(page).to have_css(
        "button.panel-command-palette__trigger[data-action='click->panels-ui--command-palette#open']" \
        "[aria-haspopup='dialog']"
      )
    end

    it "shows the placeholder text and the ⌘K shortcut hint on the pill" do
      expect(page).to have_css(".panel-command-palette__trigger-label", text: "Search dashboard pages...")
      expect(page).to have_css("kbd.panel-kbd[data-panels-ui--command-palette-target='shortcut']", text: "⌘K")
    end

    it "also renders a labelled icon-only trigger for mobile" do
      expect(page).to have_css(
        "button.panel-command-palette__trigger-icon[aria-label='Open global search']" \
        "[data-action='click->panels-ui--command-palette#open']"
      )
    end
  end

  describe "loading skeleton" do
    before { render_palette }

    it "renders a hidden skeleton target with placeholder rows inside the busy-tracked scroll region" do
      expect(page).to have_css(
        "[data-panels-ui--command-palette-target='scroll'][aria-busy='false']", visible: :all
      )
      expect(page).to have_css(
        ".panel-command-palette__skeleton[hidden][data-panels-ui--command-palette-target='loading']",
        visible: :all
      )
      expect(page).to have_css(".panel-command-palette__skeleton .panel-skeleton", minimum: 2, visible: :all)
    end
  end

  describe "search field accessibility (combobox/listbox)" do
    before { render_palette(placeholder: "Search dashboard pages...") }

    it "marks the input as a combobox controlling the listbox" do
      expect(page).to have_css(
        "input.panel-command-palette__input[role='combobox'][aria-autocomplete='list']" \
        "[aria-controls$='-listbox'][placeholder='Search dashboard pages...']"
      )
    end

    it "wires the search + keyboard actions and the input target" do
      action = page.find("input.panel-command-palette__input")["data-action"]
      expect(action).to include("input->panels-ui--command-palette#search")
      expect(action).to include("keydown->panels-ui--command-palette#onKeydown")
      expect(page).to have_css("input[data-panels-ui--command-palette-target='input']")
    end

    it "renders an empty listbox and a hidden empty-state, both targeted" do
      expect(page).to have_css("ul[role='listbox'][data-panels-ui--command-palette-target='results']")
      expect(page).to have_css("[role='status'][hidden][data-panels-ui--command-palette-target='empty']", visible: :all)
    end

    it "connects the input's aria-controls to the listbox id" do
      controls = page.find("input.panel-command-palette__input")["aria-controls"]
      expect(page).to have_css("ul##{controls}[role='listbox']")
    end
  end

  describe "custom id + class" do
    it "namespaces dialog/input/listbox ids off the supplied id and merges a class override" do
      render_palette(id: "cmdk", class: "shrink-0")
      expect(page).to have_css(".panel-command-palette.shrink-0")
      expect(page).to have_css("dialog#cmdk-dialog")
      expect(page).to have_css("input#cmdk-input")
      expect(page).to have_css("ul#cmdk-listbox")
    end
  end
end
