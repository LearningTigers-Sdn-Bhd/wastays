# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Timeline::Table, type: :component do
  let(:dates) do
    [
      { label: "Thu", metadata: "16 Jul", accessible_label: "16 July 2026", current: true },
      { label: "Fri", metadata: "17 Jul", accessible_label: "17 July 2026" }
    ]
  end

  def build_timeline(**options)
    timeline = described_class.new(
      **{ id: "stay-timeline", caption: "Hotel stays", track_count: 4 }.merge(options)
    )
    timeline.with_header(room_label: "Room", dates: dates)
    group = timeline.with_group(label: "Deluxe", count: 1, data: { testid: "deluxe-group" })
    row = group.with_row(accessible_label: "Room 101, Deluxe", data: { room: "101" })
    row.with_summary { "Room 101" }
    row.with_cell(position: 1, accessible_label: "Room 101, 16 July 2026", current: true)
    row.with_cell(position: 2, accessible_label: "Room 101, 17 July 2026")
    row.with_segment { "Reserved segment layer" }
    timeline
  end

  it "renders an accessible compound timeline with shared half-day geometry" do
    render_inline(build_timeline)

    expect(page).to have_css(
      "#stay-timeline.panel-timeline[role='table'][tabindex='0'][aria-label='Hotel stays']" \
      "[aria-describedby='stay-timeline-scroll-hint'][data-density='compact'][data-track-count='4']"
    )
    expect(page.find("#stay-timeline")[:style]).to include("--panel-timeline-track-count: 4")
    expect(page).to have_css(".panel-timeline__header[role='rowgroup'] .panel-timeline__header-row[role='row'] > .panel-timeline__room-header[role='columnheader']", text: "Room")
    expect(page).to have_css(".panel-timeline__date[role='columnheader'][aria-label='16 July 2026'][data-current='true']")
    expect(page.find(".panel-timeline__date", text: "Thu")[:style]).to eq("grid-column: 1 / span 2")
    expect(page).to have_css("[data-testid='deluxe-group'][role='rowgroup'] .panel-timeline__group-count", text: "1")
    expect(page).to have_css(".panel-timeline__row[role='row'][aria-label='Room 101, Deluxe'][data-room='101']")
    expect(page).to have_css(".panel-timeline__room-summary[role='rowheader']", text: "Room 101")
    expect(page).to have_css(".panel-timeline__cell[role='cell'][aria-label='Room 101, 16 July 2026'][data-current='true']")
    expect(page.find(".panel-timeline__cell[data-position='2']")[:style]).to eq("grid-column: 3 / span 2")
    expect(page).to have_text("Reserved segment layer")
  end

  it "supports comfortable density and caller attributes without losing component state" do
    timeline = build_timeline(
      density: :comfortable,
      class: "min-h-48",
      style: "scrollbar-gutter: stable",
      aria: { label: "Custom stay timeline" },
      data: { controller: "analytics" }
    )

    render_inline(timeline)

    expect(page).to have_css("#stay-timeline.panel-timeline.min-h-48[data-density='comfortable'][data-controller='analytics']")
    expect(page.find("#stay-timeline")[:style]).to include("--panel-timeline-track-count: 4", "scrollbar-gutter: stable")
    expect(page).to have_css("#stay-timeline[aria-label='Hotel stays']")
  end

  it "keeps day cells and segments together in one overlaid row track" do
    render_inline(build_timeline)

    expect(page).to have_css(".panel-timeline__row-track > .panel-timeline__cell", count: 2)
    expect(page).to have_css(".panel-timeline__row-track", text: "Reserved segment layer")
  end

  it "keeps every overlapping segment in the row track so none is dropped" do
    timeline = described_class.new(id: "stay-timeline", caption: "Hotel stays", track_count: 4)
    timeline.with_header(room_label: "Room", dates: dates)
    group = timeline.with_group(label: "Deluxe")
    row = group.with_row(accessible_label: "Room 101")
    row.with_summary { "Room 101" }
    row.with_cell(position: 1, accessible_label: "Day one")
    row.with_cell(position: 2, accessible_label: "Day two")
    row.with_segment { "First stay" }
    row.with_segment { "Overlapping stay" }

    render_inline(timeline)

    expect(page).to have_css(".panel-timeline__row-track", text: "First stay")
    expect(page).to have_css(".panel-timeline__row-track", text: "Overlapping stay")
  end

  it "renders a room row with day cells and no segments" do
    timeline = described_class.new(id: "stay-timeline", caption: "Hotel stays", track_count: 4)
    timeline.with_header(room_label: "Room", dates: dates)
    group = timeline.with_group(label: "Deluxe")
    row = group.with_row(accessible_label: "Room 102")
    row.with_summary { "Room 102" }
    row.with_cell(position: 1, accessible_label: "Day one")
    row.with_cell(position: 2, accessible_label: "Day two")

    render_inline(timeline)

    expect(page).to have_css(".panel-timeline__row-track > .panel-timeline__cell", count: 2)
    expect(page).to have_no_css(".panel-timeline__segment")
  end

  it "pins day cells and segments to a shared grid row so segments overlay the day grid" do
    stylesheet = Rails.root.join("app/assets/tailwind/panel/timeline.css").read

    expect(stylesheet).to match(/\.panel-timeline__cell\s*\{[^}]*grid-row:\s*1\b/m)
    expect(stylesheet).to match(/\.panel-timeline__segment\s*\{[^}]*grid-row:\s*1\b/m)
  end

  it "owns row groups through a presentational body so the table structure is unbroken" do
    render_inline(build_timeline)

    expect(page).to have_css(".panel-timeline[role='table'] > .panel-timeline__body[role='presentation']")
    expect(page).to have_css(".panel-timeline__body[role='presentation'] > .panel-timeline__group[role='rowgroup']")
  end

  it "derives a stable dom id and scroll-hint id from the caption when no id is supplied" do
    timeline = described_class.new(caption: "Front desk stays", track_count: 4)
    timeline.with_header(room_label: "Room", dates: dates)

    render_inline(timeline)

    expect(page).to have_css("#timeline-front-desk-stays[aria-describedby='timeline-front-desk-stays-scroll-hint']")
  end

  it "renders static and clipped segments with semantic state and non-color continuation hooks" do
    render_inline(PanelsUI::Timeline::Segment.new(
      start_track: 1,
      end_track: 5,
      accessible_label: "Maintenance continues beyond the visible range",
      tone: :warning,
      emphasis: :hatched,
      clipped_left: true,
      clipped_right: true,
      data: { operation: "maintenance" }
    )) { "Maintenance" }

    expect(page).to have_css(
      ".panel-timeline__segment[data-tone='warning'][data-emphasis='hatched']" \
      "[data-clipped-left='true'][data-clipped-right='true'][data-operation='maintenance']"
    )
    expect(page.find(".panel-timeline__segment")[:style]).to eq("grid-column: 1 / 5")
    expect(page).to have_css(".panel-timeline__segment-content[role='img'][aria-label='Maintenance continues beyond the visible range']", text: "Maintenance")
    expect(page).to have_no_link
  end

  it "gives actionable segments their complete accessible label and focus class" do
    render_inline(PanelsUI::Timeline::Segment.new(
      start_track: 2,
      end_track: 4,
      accessible_label: "Ada Lovelace, confirmed, room 101",
      href: "/bookings/1",
      link_attributes: { data: { turbo_frame: "booking" }, class: "custom-link" }
    )) { "Ada" }

    expect(page).to have_css(
      "a.panel-timeline__segment-action.custom-link[href='/bookings/1']" \
      "[aria-label='Ada Lovelace, confirmed, room 101'][data-turbo-frame='booking']",
      text: "Ada"
    )
  end

  validation_cases = {
    "a blank caption" => [ { caption: "", track_count: 4 }, /caption is required/ ],
    "an odd track count" => [ { caption: "Stays", track_count: 3 }, /positive even integer/ ],
    "an unsupported density" => [ { caption: "Stays", track_count: 4, density: :dense }, /density must be/ ],
    "a missing header" => [ { caption: "Stays", track_count: 4 }, /header slot is required/ ]
  }

  validation_cases.each do |description, (options, error)|
    it "rejects #{description}" do
      component = described_class.new(**options)
      component.with_header(room_label: "Room", dates: dates) unless description == "a missing header"

      expect { render_inline(component) }.to raise_error(ArgumentError, error)
    end
  end

  it "rejects date columns and cells that do not match the shared geometry" do
    timeline = described_class.new(caption: "Stays", track_count: 4)
    timeline.with_header(room_label: "Room", dates: dates.first(1))

    expect { render_inline(timeline) }.to raise_error(ArgumentError, /dates must match/)

    timeline = described_class.new(caption: "Stays", track_count: 4)
    timeline.with_header(room_label: "Room", dates: dates)
    group = timeline.with_group(label: "Deluxe")
    row = group.with_row(accessible_label: "Room 101")
    row.with_summary { "101" }
    row.with_cell(position: 2, accessible_label: "Second day")

    expect { render_inline(timeline) }.to raise_error(ArgumentError, /cells must match|consecutive one-based/)
  end

  it "rejects invalid segment geometry and semantic variants" do
    expect do
      render_inline(PanelsUI::Timeline::Segment.new(
        start_track: 4, end_track: 2, accessible_label: "Invalid"
      )) { "Invalid" }
    end.to raise_error(ArgumentError, /positive increasing range/)

    expect do
      render_inline(PanelsUI::Timeline::Segment.new(
        start_track: 1, end_track: 2, accessible_label: "Invalid", tone: :purple
      )) { "Invalid" }
    end.to raise_error(ArgumentError, /tone must be/)
  end

  it "keeps the primitive stylesheet on semantic portal tokens" do
    stylesheet = Rails.root.join("app/assets/tailwind/panel/timeline.css").read

    expect(stylesheet).not_to match(/\b(?:slate|gray|stone|indigo|blue|red|green|purple)-\d/)
    expect(stylesheet).to include("var(--card)", "var(--border)", "var(--status-warning-background)", "var(--ring)")
  end
end
