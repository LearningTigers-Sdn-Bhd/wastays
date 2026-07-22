# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Table, type: :component do
  def render_table(**options, &block)
    render_inline(described_class.new(caption: "Guests", **options), &block)
  end

  def with_required_slots(table)
    table.with_header { "<tr><th scope=\"col\">Guest</th></tr>".html_safe }
    table.with_body { "<tr><td>Jamie Tan</td></tr>".html_safe }
  end

  it "renders a hidden caption and structured sections in semantic order" do
    render_table do |table|
      with_required_slots(table)
      table.with_footer { "<tr><td>Total: 1</td></tr>".html_safe }
    end

    expect(page).to have_css(".panel-table__wrapper > table.panel-table > caption.sr-only + thead + tbody + tfoot")
    expect(page).to have_css("caption.sr-only", text: "Guests", visible: :all)
  end

  it "escapes caption text while preserving captured slot HTML" do
    render_inline(described_class.new(caption: "<script>alert('caption')</script>")) do |table|
      table.with_header { "<tr><th scope=\"col\"><strong>Guest</strong></th></tr>".html_safe }
      table.with_body { "<tr><td><a href=\"/guests/1\">Jamie</a></td></tr>".html_safe }
    end

    expect(page).to have_no_css("script")
    expect(page).to have_css("caption", text: "<script>alert('caption')</script>", visible: :all)
    expect(page).to have_css("thead th strong", text: "Guest")
    expect(page).to have_css("tbody td a[href='/guests/1']", text: "Jamie")
  end

  it "requires a nonblank caption, header, and body" do
    expect do
      render_inline(described_class.new(caption: "")) { |table| with_required_slots(table) }
    end.to raise_error(ArgumentError, /caption/)

    expect do
      render_table { |table| table.with_body { "<tr><td>Guest</td></tr>".html_safe } }
    end.to raise_error(ArgumentError, /header/)

    expect do
      render_table { |table| table.with_header { "<tr><th>Guest</th></tr>".html_safe } }
    end.to raise_error(ArgumentError, /body/)
  end

  it "applies supported variants and boolean behaviors" do
    render_table(density: :compact, striped: true, hoverable: true, sticky_header: true, bordered: false) do |table|
      with_required_slots(table)
    end

    expect(page).to have_css(
      "table.panel-table[data-density='compact'][data-striped='true'][data-hoverable='true']" \
      "[data-sticky-header='true'][data-bordered='false']"
    )
  end

  it "falls back to the default density" do
    render_table(density: :dense) { |table| with_required_slots(table) }

    expect(page).to have_css("table.panel-table[data-density='default']")
  end

  it "supports opt-in sentence-case headers without changing the default" do
    render_table(header_style: :sentence, density: :compact) { |table| with_required_slots(table) }
    expect(page).to have_css("table.panel-table[data-header-style='sentence'][data-density='compact']")

    render_table(header_style: :unknown) { |table| with_required_slots(table) }
    expect(page).to have_css("table.panel-table[data-header-style='default']")
  end

  it "keeps the compact legacy header size unless sentence-case headers are requested" do
    stylesheet = Rails.root.join("app/assets/tailwind/panel/table.css").read

    expect(stylesheet).to match(
      /\.panel-table thead th\s*\{[^}]*font-size:\s*0\.6875rem;/m
    )
    expect(stylesheet).to match(
      /\.panel-table\[data-header-style="sentence"\] thead th\s*\{[^}]*font-size:\s*0\.75rem;/m
    )
  end

  it "merges table and wrapper classes and preserves standard HTML attributes" do
    render_table(
      class: "min-w-[48rem]",
      wrapper_class: "rounded-xl",
      id: "guest-table",
      aria: { describedby: "guest-help" },
      data: { testid: "guest-table" }
    ) { |table| with_required_slots(table) }

    expect(page).to have_css(".panel-table__wrapper.rounded-xl > table#guest-table.panel-table.min-w-\\[48rem\\][aria-describedby='guest-help'][data-testid='guest-table']")
  end

  it "leaves empty-state structure and colspan under caller control" do
    render_table do |table|
      table.with_header { "<tr><th scope=\"col\">Guest</th><th scope=\"col\">Status</th></tr>".html_safe }
      table.with_body do
        "<tr><td colspan=\"2\"><p>No guests have checked out today.</p></td></tr>".html_safe
      end
    end

    expect(page).to have_css("tbody > tr > td[colspan='2'] p", text: "No guests have checked out today.")
  end
end
