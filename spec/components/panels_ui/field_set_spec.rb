# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::FieldSet, type: :component do
  it "renders a semantic fieldset with a legend and yielded content" do
    render_inline(described_class.new(legend: "Preferences")) { "inner" }

    expect(page).to have_css("fieldset.panel-field-set")
    expect(page).to have_css("legend.panel-field-set__legend[data-variant='legend']", text: "Preferences")
    expect(page).to have_css("fieldset.panel-field-set", text: "inner")
  end

  it "links the description via aria-describedby" do
    render_inline(described_class.new(legend: "Profile", description: "Shown on invoices.")) { "inner" }

    description = page.find("p.panel-field-set__description", text: "Shown on invoices.")
    expect(page).to have_css("fieldset[aria-describedby='#{description[:id]}']")
  end

  it "supports the label legend variant" do
    render_inline(described_class.new(legend: "Notifications", legend_variant: :label)) { "inner" }

    expect(page).to have_css("legend.panel-field-set__legend[data-variant='label']", text: "Notifications")
  end

  it "omits the legend and description when not given" do
    render_inline(described_class.new) { "inner" }

    expect(page).to have_no_css("legend")
    expect(page).to have_no_css("p.panel-field-set__description")
    expect(page).to have_css("fieldset.panel-field-set", text: "inner")
  end
end
