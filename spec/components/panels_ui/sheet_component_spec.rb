# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::SheetComponent, type: :component do
  def render_sheet(**opts, &block)
    render_inline(described_class.new(**{ id: "s1", title: "Sheet title" }.merge(opts)), &block)
  end

  describe "structure and accessibility" do
    before do
      render_sheet(description: "A short summary") do |sheet|
        sheet.with_body { "Body copy" }
        sheet.with_footer { '<button type="button">Save</button>'.html_safe }
      end
    end

    it "renders a native modal dialog with the sheet controller" do
      expect(page).to have_css("dialog[aria-modal='true'][data-controller='panels-ui--sheet']")
      expect(page).to have_css("dialog[data-panels-ui-sheet-side='right']")
    end

    it "stays hidden until opened" do
      classes = page.find("dialog")[:class].split
      expect(classes).to include("hidden", "open:flex")
      expect(classes).not_to include("flex")
    end

    it "wires its visible title and description to the dialog" do
      expect(page).to have_css("dialog[aria-labelledby='s1-title'][aria-describedby='s1-desc']")
      expect(page).to have_css(
        "h2#s1-title[tabindex='-1'][data-panels-ui--sheet-target='initialFocus']",
        text: "Sheet title"
      )
      expect(page).to have_css("p#s1-desc", text: "A short summary")
    end

    it "renders body and footer slots" do
      expect(page).to have_text("Body copy")
      expect(page).to have_button("Save")
      expect(page).to have_css("footer.border-t.border-border.bg-muted\\/50")
    end

    it "renders a labelled animated close affordance" do
      expect(page).to have_css("button[aria-label='Close'][data-action='panels-ui--sheet#close']")
    end
  end

  describe "accessible naming" do
    it "supports an explicit label without a visible title" do
      render_sheet(title: nil, aria_label: "Account options") { |sheet| sheet.with_body { "x" } }

      expect(page).to have_css("dialog[aria-label='Account options']")
      expect(page).to have_no_css("dialog[aria-labelledby]")
    end

    it "rejects a sheet without an accessible name" do
      expect { render_sheet(title: nil) }.to raise_error(
        ArgumentError,
        "Sheet requires a visible title or an aria_label"
      )
    end
  end

  describe "dismissible: false" do
    it "removes the close affordance and exposes the controller value" do
      render_sheet(dismissible: false) { |sheet| sheet.with_body { "x" } }

      expect(page).to have_no_css("button[aria-label='Close']")
      expect(page).to have_css("dialog[data-panels-ui--sheet-dismissible-value='false']")
    end
  end

  describe "side and size variants" do
    side_classes = {
      right: "translate-x-full",
      left: "-translate-x-full",
      top: "-translate-y-full",
      bottom: "translate-y-full"
    }
    size_classes = {
      right: { sm: "w-[20rem]", md: "w-[28rem]", lg: "w-[36rem]", full: "w-dvw" },
      left: { sm: "w-[20rem]", md: "w-[28rem]", lg: "w-[36rem]", full: "w-dvw" },
      top: { sm: "h-[20rem]", md: "h-[28rem]", lg: "h-[36rem]", full: "h-dvh" },
      bottom: { sm: "h-[20rem]", md: "h-[28rem]", lg: "h-[36rem]", full: "h-dvh" }
    }

    side_classes.each do |side, side_class|
      size_classes.fetch(side).each do |size, size_class|
        it "applies the #{side} #{size} classes" do
          render_sheet(side: side, size: size) { |sheet| sheet.with_body { "x" } }
          classes = page.find("dialog")[:class]

          expect(classes).to include(side_class, size_class)
          expect(classes).to include("rounded-none") if size == :full
        end
      end
    end

    it "falls back to right and md for unknown variants" do
      render_sheet(side: :diagonal, size: :huge, variant: :detached) { |sheet| sheet.with_body { "x" } }
      classes = page.find("dialog")[:class]

      expect(classes).to include("right-0", "translate-x-full", "w-[28rem]")
      expect(page).to have_css("dialog[data-panels-ui-sheet-variant='edge']")
    end

    {
      right: %w[top-4 bottom-4 right-4 rounded-lg],
      left: %w[top-4 bottom-4 left-4 rounded-lg],
      top: %w[inset-x-4 top-4 rounded-lg],
      bottom: %w[inset-x-4 bottom-4 rounded-lg]
    }.each do |side, expected_classes|
      it "frames the floating #{side} variant inside the viewport" do
        render_sheet(side: side, variant: :floating) { |sheet| sheet.with_body { "x" } }
        classes = page.find("dialog")[:class].split

        expect(classes).to include(*expected_classes)
        expect(page).to have_css("dialog[data-panels-ui-sheet-variant='floating']")
      end
    end

    it "keeps a full floating sheet inside its frame with rounded corners" do
      render_sheet(variant: :floating, size: :full) { |sheet| sheet.with_body { "x" } }
      classes = page.find("dialog")[:class]

      expect(classes).to include("w-[calc(100dvw-2rem)]", "rounded-lg")
      expect(classes).not_to include("w-dvw", "rounded-none")
    end

    it "lets a caller class override conflicting component classes" do
      render_sheet(class: "w-[40rem] rounded-2xl") { |sheet| sheet.with_body { "x" } }
      classes = page.find("dialog")[:class]

      expect(classes).to include("w-[40rem]", "rounded-2xl")
      expect(classes).not_to include("w-[28rem]", "rounded-l-lg")
    end
  end
end
