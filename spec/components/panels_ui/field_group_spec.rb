# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::FieldGroup, type: :component do
  it "wraps its content in a spacing container" do
    render_inline(described_class.new) { "inner" }

    expect(page).to have_css("div.panel-field-group", text: "inner")
  end

  it "merges caller classes and passes through attributes" do
    render_inline(described_class.new(class: "mt-4", data: { testid: "group" })) { "inner" }

    expect(page).to have_css("div.panel-field-group.mt-4[data-testid='group']")
  end
end
