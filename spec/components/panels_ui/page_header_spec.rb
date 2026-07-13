# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::PageHeader, type: :component do
  it "renders a title and optional subtitle without shell spacing or breadcrumbs" do
    render_inline(described_class.new(title: "Reservations", subtitle: "Manage upcoming stays"))

    expect(page).to have_css("header.panel-page-header")
    expect(page).to have_css("h1.panel-page-header__title", text: "Reservations")
    expect(page).to have_css(".panel-page-header__subtitle", text: "Manage upcoming stays")
    expect(page).to have_no_css(".panel-page-header__actions")
    expect(page).to have_no_css("nav")
  end

  it "renders developer-supplied actions in the responsive actions region" do
    render_inline(described_class.new(title: "Reservations")) do |header|
      header.with_actions { '<button type="button">New reservation</button>'.html_safe }
    end

    expect(page).to have_css(".panel-page-header__actions")
    expect(page).to have_button("New reservation")
  end

  it "merges custom classes and HTML attributes" do
    render_inline(described_class.new(
      title: "Reservations",
      id: "reservations-header",
      class: "custom-header",
      data: { testid: "page-header" }
    ))

    expect(page).to have_css("header#reservations-header.panel-page-header.custom-header[data-testid='page-header']")
  end

  it "supports a valid alternate title tag and falls back to h1" do
    render_inline(described_class.new(title: "Preview", title_as: :h3))
    expect(page).to have_css("h3.panel-page-header__title", text: "Preview")

    render_inline(described_class.new(title: "Fallback", title_as: :div))
    expect(page).to have_css("h1.panel-page-header__title", text: "Fallback")
  end

  it "requires a title" do
    expect { render_inline(described_class.new(title: nil)) }
      .to raise_error(ArgumentError, "Page headers require a title")
  end
end
