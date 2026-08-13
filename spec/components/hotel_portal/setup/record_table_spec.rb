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

  # The cells hold controls whose own labels are hidden at table widths, so a
  # column that needs explaining has only its header to say it in.
  describe "columns that explain themselves" do
    def render_explained
      render_inline(described_class.new(caption: "Extra charges", add_label: "Add", empty: "None")) do |table|
        table.with_column(label: "Name")
        table.with_column(label: "Price", hint: "Leave it empty when staff decide the amount.")
        table.with_column(label: "Charged") { "<p>Per stay bills once for the booking.</p>".html_safe }
        table.with_blank_row(remove_label: "Remove this") { "<td></td><td></td><td></td>".html_safe }
      end
    end

    it "puts a sentence in a tooltip the trigger also names for assistive tech" do
      render_explained

      header = page.find("thead th", text: "Price")
      expect(header).to have_css("button.panel-record-table__hint[aria-label='Price: Leave it empty when staff decide the amount.']")
      expect(header).to have_css("[role='tooltip']", text: "Leave it empty when staff decide the amount.", visible: :all)
    end

    it "puts longer guidance in a popover opened the same way the tooltip is" do
      render_explained

      header = page.find("thead th", text: "Charged")
      expect(header).to have_css("button.panel-record-table__hint[aria-label='About Charged'][aria-haspopup='dialog']")
      expect(header).to have_css("[data-panels-ui--popover-trigger-on-value='hover']")
      expect(header).to have_css("#record-table-help-charged-panel", text: "Per stay bills once for the booking.", visible: :all)
    end

    it "leaves a column that needs no explaining unmarked" do
      render_explained

      expect(page.find("thead th", text: "Name")).to have_no_css(".panel-record-table__hint")
    end
  end

  it "hides the empty state while records exist and shows it when none do" do
    render_table(rows: 1)
    expect(page.find("tr.panel-record-table__empty", visible: :all)).to be_present
    expect(page).to have_no_css("tr.panel-record-table__empty")

    render_table(rows: 0)
    expect(page).to have_css("tr.panel-record-table__empty", text: "No extra charges yet.")
  end

  # An empty table states what is missing, what to do about it, and offers the
  # one action that fixes it — rather than a line of grey text with the add
  # button somewhere below the fold of the row.
  describe "the empty state" do
    it "states the case with an icon, a description and its own add action" do
      render_table(rows: 0, empty: "No extra charges yet",
                   empty_description: "If this property sells nothing beyond the room, continue.",
                   empty_icon: "concierge-bell")

      state = page.find("tr.panel-record-table__empty")
      expect(state).to have_css(".panel-record-table__empty-icon svg")
      expect(state).to have_css(".panel-record-table__empty-title", text: "No extra charges yet")
      expect(state).to have_css(".panel-record-table__empty-description",
                                text: "If this property sells nothing beyond the room, continue.")
      expect(state).to have_button("Add extra charge")
    end

    # Two add buttons on screen at once would be the same offer twice, and the
    # footer's sits below a block that already carries it.
    it "stands the add footer down while it shows, and back up once a record exists" do
      render_table(rows: 0)
      expect(page).to have_css("tfoot tr[hidden]", visible: :all)
      expect(page).to have_button("Add extra charge", count: 1)

      render_table(rows: 1)
      expect(page).to have_no_css("tfoot tr[hidden]", visible: :all)
      expect(page).to have_button("Add extra charge", count: 1)
    end

    # A message-only footer says something about the table as a whole, so it is
    # not the empty state's to hide.
    it "leaves a message-only footer in place" do
      render_inline(described_class.new(
        caption: "Standard pricing", empty: "No rooms yet", removable: false,
        addable: false, footer_message: "All room categories are assigned."
      )) do |table|
        table.with_column(label: "Room")
      end

      expect(page).to have_text("All room categories are assigned.")
      expect(page).to have_no_css("tfoot tr[hidden]", visible: :all)
    end
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

  # Pinning columns is the only thing the spreadsheet variant decides. Density and
  # the scrollable region are the same either way, so the two variants read as one
  # table with more or fewer columns rather than as two kinds of table.
  it "renders both variants at one density inside a reachable, named scroll region" do
    render_table
    expect(page).to have_css("[role='region'][tabindex='0'][aria-label='Extra charges'] table[data-density='compact']")
    expect(page).to have_no_css("table.panel-record-table--spreadsheet")

    render_table(spreadsheet: true)
    expect(page).to have_css("[role='region'][tabindex='0'][aria-label='Extra charges'] table[data-density='compact']")
  end

  it "supports a horizontally scrollable spreadsheet with a trailing Actions column" do
    render_table(spreadsheet: true, actions: true)

    expect(page).to have_css("[role='region'][tabindex='0'][aria-label='Extra charges']")
    expect(page).to have_css("table.panel-record-table--spreadsheet[data-sticky-header='true']")
    expect(page.all("thead th").map(&:text)).to eq([ "Remove", "Name*", "Amount", "Actions" ])
    expect(page).to have_css("tr.panel-record-table__empty td[colspan='4']", visible: :all)
  end

  it "preserves a caller class used to define a spreadsheet's fixed column widths" do
    render_table(spreadsheet: true, actions: true, class: "panel-record-table--rooms")

    expect(page).to have_css(
      "[role='region'][aria-label='Extra charges'] > .panel-table__wrapper > table.panel-record-table--spreadsheet.panel-record-table--rooms"
    )
  end

  it "marks persisted rows for confirmed deferred removal" do
    render_inline(described_class.new(
      caption: "Rooms", add_label: "Add room", empty: "No rooms", spreadsheet: true, actions: true
    )) do |table|
      table.with_column(label: "Name")
      table.with_row(
        remove_label: "Remove Deluxe",
        persisted: true,
        confirm: "Remove Deluxe?",
        key: "room-1"
      ) { "<td>Deluxe</td><td>Manage</td>".html_safe }
      table.with_blank_row(remove_label: "Remove this room", key: "NEW_RECORD") { "<td></td><td></td>".html_safe }
    end

    expect(page).to have_css("tr[data-record-table-persisted='true'][data-record-table-key='room-1']")
    expect(page).to have_css("button[data-record-table-confirm='Remove Deluxe?']")
  end

  it "supports protected rows and a message-only footer without changing existing callers" do
    render_inline(described_class.new(
      caption: "Standard pricing", empty: "No rooms", removable: false,
      addable: false, footer_message: "All room categories are assigned."
    )) do |table|
      table.with_column(label: "Room")
      table.with_row(remove_label: "Remove Deluxe", removable: false) { "<td>Deluxe</td>".html_safe }
    end

    expect(page.all("thead th").map(&:text)).to eq([ "Room" ])
    expect(page).to have_no_button("Remove Deluxe")
    expect(page).to have_text("All room categories are assigned.")
    expect(page).to have_css("tr.panel-record-table__empty td[colspan='1']", visible: :all)
  end

  describe "grouped records" do
    def render_grouped
      render_inline(described_class.new(
        caption: "Rate plans", empty: "No room pricing yet.", addable: false
      )) do |table|
        table.with_column(label: "Room category", required: true)
        table.with_column(label: "Base rate")

        table.with_group_row(key: "standard", locked: true, locked_reason: "Protected") do
          "<span>Standard rate</span>".html_safe
        end
        table.with_row(remove_label: "Remove Deluxe", removable: false) { "<td>Deluxe</td><td>380</td>".html_safe }

        table.with_group_row(key: "plan-1", remove_label: "Remove Weekend package",
                             persisted: true, confirm: "Remove Weekend package?", add_label: "Room") do
          "<span>Weekend package</span>".html_safe
        end
        table.with_row(remove_label: "Remove Twin") { "<td>Twin</td><td>290</td>".html_safe }
        table.with_group_template_row(group: "plan-1", remove_label: "Remove this room", key: "NEW_RECORD") do
          "<td></td><td></td>".html_safe
        end
      end
    end

    it "keeps headings, records and clone templates in the order the caller wrote them" do
      render_grouped

      body = page.find("tbody", visible: :all)
      expect(body.all("> *", visible: :all).map { |node| [ node.tag_name, node[:class] ] }).to eq([
        [ "tr", "panel-record-table__group" ],
        [ "tr", "panel-record-table__row" ],
        [ "tr", "panel-record-table__group" ],
        [ "tr", "panel-record-table__row" ],
        [ "template", nil ],
        [ "tr", "panel-record-table__empty" ]
      ])
    end

    # A row that opts out of removal used to omit the cell entirely while the
    # header kept the column, sliding every cell after it one column left.
    it "holds the control column open on rows that cannot be removed" do
      render_grouped

      header_count = page.all("thead th").size
      cell_counts = page.all("tbody tr.panel-record-table__row").map { |row| row.all("td", visible: :all).size }

      expect(cell_counts).to all(eq(header_count))
      expect(page).to have_css("tr.panel-record-table__row td.panel-record-table__control", count: 2)
    end

    it "spans the heading label across the record columns, clear of the control column" do
      render_grouped

      expect(page).to have_css("tr.panel-record-table__group td.panel-record-table__group-label[colspan='2']", count: 2)
    end

    it "locks a protected group and offers removal on the rest" do
      render_grouped

      groups = page.all("tr.panel-record-table__group")
      expect(groups.first).to have_css("[aria-label='Protected'] svg")
      expect(groups.first).to have_no_css("button")
      expect(groups.last).to have_css("button[aria-label='Remove Weekend package'][data-record-table-confirm='Remove Weekend package?']")
    end

    it "points each group's add button at that group's own template" do
      render_grouped

      expect(page).to have_css("button[data-record-table-group-param='plan-1']", text: "Room")
      expect(rendered_content).to include(%(data-record-table-group="plan-1"))
    end

    it "answers the empty state on records alone, not on the headings above them" do
      render_inline(described_class.new(caption: "Rate plans", empty: "No room pricing yet.", addable: false)) do |table|
        table.with_column(label: "Room category")
        table.with_group_row(key: "standard", locked: true) { "<span>Standard rate</span>".html_safe }
      end

      expect(page).to have_css("tr.panel-record-table__empty", text: "No room pricing yet.")
    end
  end

  it "renders a disabled final-row removal with its explanation" do
    render_inline(described_class.new(caption: "Assignments", empty: "None", removable: true, addable: false)) do |table|
      table.with_column(label: "Room")
      table.with_row(
        remove_label: "Remove Deluxe", removable: false,
        remove_disabled_reason: "A rate plan must keep one room."
      ) { "<td>Deluxe</td>".html_safe }
    end

    expect(page).to have_css("button[aria-label='Remove Deluxe'][disabled]")
    expect(page).to have_css("button[title='A rate plan must keep one room.']")
  end
end
