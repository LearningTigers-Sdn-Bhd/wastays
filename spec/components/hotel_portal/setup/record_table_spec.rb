# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Setup::RecordTable, type: :component do
  def render_table(rows: 1, **options)
    render_inline(described_class.new(
      caption: "Extra charges",
      add_label: "Add extra charge",
      empty: "No extra charges yet.",
      **options
    )) do |table|
      table.with_column(label: "Name", required: true)
      table.with_column(label: "Amount")

      rows.times do |index|
        table.with_row(remove_label: "Remove charge #{index}") { "<td>Breakfast</td><td>25.00</td>".html_safe }
      end

      table.with_blank_row(remove_label: "Remove this extra charge") { "<td></td><td></td>".html_safe }
    end
  end

  it "leads with a named Remove column rather than an Actions column" do
    render_table

    headers = page.all("thead th").map(&:text)

    expect(headers.first).to eq("Remove")
    expect(headers).not_to include("Actions")
  end

  it "names the record in each row's remove control" do
    render_table(rows: 2)

    expect(page).to have_css("tbody tr[data-record-table-target='row']", count: 2)
    expect(page).to have_css("button[aria-label='Remove charge 0'] svg")
    expect(page).to have_css("button[aria-label='Remove charge 1'] svg")
  end

  it "marks required columns in the header, where the hidden field label cannot" do
    render_table

    expect(page.find("thead th", text: "Name")).to have_css(".panel-record-table__required")
    expect(page.find("thead th", text: "Amount")).to have_no_css(".panel-record-table__required")
  end

  it "hides the empty state while records exist and shows it when none do" do
    render_table(rows: 1)
    expect(page.find("tr.panel-record-table__empty", visible: :all)).to be_present
    expect(page).to have_no_css("tr.panel-record-table__empty")

    render_table(rows: 0)
    expect(page).to have_css("tr.panel-record-table__empty", text: "No extra charges yet.")
  end

  it "carries a blank row the add action can clone, placed ahead of the empty state" do
    render_table

    body = page.find("tbody", visible: :all)

    # The row inside the <template> is asserted against the raw output: the test
    # helper's HTML4 parser has no notion of <template> and discards its contents.
    expect(rendered_content).to include(%(<template data-record-table-target="template"><tr class="panel-record-table__row"))
    expect(body.all("> *", visible: :all).map(&:tag_name)).to eq(%w[tr template tr])
    expect(page).to have_button("Add extra charge")
  end

  it "spans the control column when stating the empty case" do
    render_table(rows: 0)

    expect(page).to have_css("tr.panel-record-table__empty td[colspan='3']")
  end

  it "refuses to render without the pieces the add action depends on" do
    expect {
      render_inline(described_class.new(caption: "Extras", add_label: "Add", empty: "None")) do |table|
        table.with_column(label: "Name")
      end
    }.to raise_error(ArgumentError, /blank_row/)
  end
end
