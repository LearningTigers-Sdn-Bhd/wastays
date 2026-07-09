# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::DialogComponent, type: :component do
  def render_dialog(**opts, &block)
    render_inline(described_class.new(**{ id: "d1" }.merge(opts)), &block)
  end

  describe "structure & accessibility" do
    before do
      render_dialog(title: "Title here", description: "A short summary") do |dialog|
        dialog.with_body { "Body copy" }
        dialog.with_footer { '<button type="button">OK</button>'.html_safe }
      end
    end

    it "renders a native <dialog> marked as a modal" do
      expect(page).to have_css("dialog[aria-modal='true']")
    end

    it "stays out of document flow until the native dialog is open" do
      classes = page.find("dialog")[:class]
      expect(classes).to include("hidden")
      expect(classes).to include("open:flex")
      expect(classes.split).not_to include("flex")
    end

    it "carries the controller directly on the <dialog> (no wrapper, no trigger)" do
      expect(page).to have_css("dialog[data-controller='panels-ui--dialog']")
      expect(page).to have_no_css("[data-panels-ui--dialog-target='dialog']")
      expect(page).to have_no_css("button", text: "Open") # component renders no trigger
    end

    it "renders the string title and wires aria-labelledby to it" do
      expect(page).to have_css("dialog[aria-labelledby='d1-title']")
      expect(page).to have_css("h2#d1-title[tabindex='-1'][data-panels-ui--dialog-target='initialFocus']", text: "Title here")
    end

    it "renders the string description and wires aria-describedby to it" do
      expect(page).to have_css("dialog[aria-describedby='d1-desc']")
      expect(page).to have_css("p#d1-desc", text: "A short summary")
    end

    it "yields the body and footer slots" do
      expect(page).to have_text("Body copy")
      expect(page).to have_button("OK")
      expect(page).to have_css("footer.border-t.border-border.bg-muted\\/50")
    end

    it "exposes a labelled close affordance with its Stimulus action" do
      expect(page).to have_css("button[aria-label='Close'][data-action='panels-ui--dialog#close']")
    end
  end

  describe "optional title / description" do
    it "uses an explicit accessible label when no visible title is given" do
      render_dialog(aria_label: "Account details", description: "Only a description") do |dialog|
        dialog.with_body { "x" }
      end
      expect(page).to have_css("dialog[aria-describedby='d1-desc']")
      expect(page).to have_css("dialog[aria-label='Account details']")
      expect(page).to have_no_css("dialog[aria-labelledby]")
      expect(page).to have_no_css("h2#d1-title")
    end

    it "rejects a dialog without an accessible name" do
      expect { render_dialog(description: "Not a name") }.to raise_error(
        ArgumentError,
        "Dialog requires a visible title or an aria_label"
      )
    end

    it "omits aria-describedby when no description is given" do
      render_dialog(title: "Only a title") { |dialog| dialog.with_body { "x" } }
      expect(page).to have_css("dialog[aria-labelledby='d1-title']")
      expect(page).to have_no_css("dialog[aria-describedby]")
      expect(page).to have_no_css("p#d1-desc")
    end
  end

  describe "dismissible: false" do
    it "does not render the close button" do
      render_dialog(dismissible: false, title: "T") { |dialog| dialog.with_body { "x" } }
      expect(page).to have_no_css("button[aria-label='Close']")
      expect(page).to have_css("dialog[data-panels-ui--dialog-dismissible-value='false']")
    end
  end

  describe "size variants (tw_merge-resolved classes)" do
    {
      sm:          "max-w-sm",
      md:          "max-w-md",
      lg:          "max-w-lg",
      almost_full: "w-[calc(100vw-3rem)]"
    }.each do |size, klass|
      it "applies #{klass} for size: #{size}" do
        render_dialog(size: size, title: "Example") { |dialog| dialog.with_body { "x" } }
        expect(page.find("dialog")[:class]).to include(klass)
      end
    end

    it "makes the full variant edge-to-edge with no rounding" do
      render_dialog(size: :full, title: "Example") { |dialog| dialog.with_body { "x" } }
      classes = page.find("dialog")[:class]
      expect(classes).to include("w-screen")
      expect(classes).to include("rounded-none")
      expect(classes).not_to include("rounded-lg") # base rounding dropped
    end

    it "falls back to the md default for an unknown size" do
      render_dialog(size: :bogus, title: "Example") { |dialog| dialog.with_body { "x" } }
      expect(page.find("dialog")[:class]).to include("max-w-md")
    end

    it "merges a caller class override, letting it win over base conflicts" do
      render_dialog(size: :md, title: "Example", class: "max-w-md rounded-2xl") do |dialog|
        dialog.with_body { "x" }
      end
      classes = page.find("dialog")[:class]
      expect(classes).to include("rounded-2xl")
      expect(classes).not_to include("rounded-lg") # base rounded-lg replaced by override
    end
  end
end
