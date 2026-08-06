# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Kbd, type: :component do
  it "renders a single key with block content and caller attributes" do
    render_inline(described_class.new(size: :lg, class: "ml-1", id: "enter", data: { testid: "key" })) { "Enter" }

    expect(page).to have_css("kbd#enter.panel-kbd.ml-1[data-size='lg'][data-testid='key']", text: "Enter")
  end

  it "renders a keyboard combination as individually styled keys" do
    render_inline(described_class.new(keys: [ "Ctrl", "Shift", "P" ], separator: "+", aria: { label: "Open command palette" }))

    expect(page).to have_css("span[role='group'][aria-label='Open command palette'] kbd.panel-kbd", count: 3)
    expect(page).to have_css("span.panel-kbd__separator[aria-hidden='true']", text: "+", count: 2)
  end

  it "supports all sizes, plain styling, and option fallbacks" do
    described_class::SIZES.each do |size|
      render_inline(described_class.new(label: size, size: size, variant: :plain))
      expect(page).to have_css("kbd.panel-kbd[data-size='#{size}'][data-variant='plain']", text: size.to_s)
    end
    render_inline(described_class.new(label: "Fallback", size: :huge, variant: :unknown))
    expect(page).to have_css("kbd.panel-kbd[data-size='md']:not([data-variant])", text: "Fallback")
  end
end
