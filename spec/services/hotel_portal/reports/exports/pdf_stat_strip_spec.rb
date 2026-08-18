# frozen_string_literal: true

require "rails_helper"
require "pdf-reader"

RSpec.describe HotelPortal::Reports::Exports::PdfStatStrip do
  let(:theme) { HotelPortal::Reports::Exports::PdfTheme }

  def document(page_layout: :portrait)
    Prawn::Document.new(page_size: "A4", page_layout: page_layout, margin: theme::PAGE_MARGIN).tap do |pdf|
      theme.configure_font(pdf)
    end
  end

  # Height consumed by the strip, which is what the wrapping and page-fit rules are about.
  def drawn_height(pdf, metrics)
    before = pdf.cursor
    described_class.new(pdf: pdf).draw(metrics)
    before - pdf.cursor
  end

  def extracted_text(pdf) = PDF::Reader.new(StringIO.new(pdf.render)).pages.map(&:text).join("\n")

  it "upcases labels and prints values as given" do
    pdf = document
    described_class.new(pdf: pdf).draw([ [ "Bookings Engaged", "65" ], [ "Net Revenue", "MYR 84,648.64" ] ])
    text = extracted_text(pdf)

    expect(text).to include("BOOKINGS ENGAGED", "65", "NET REVENUE", "MYR 84,648.64")
    expect(text).not_to include("Bookings Engaged")
  end

  it "draws nothing for no metrics" do
    pdf = document

    expect(drawn_height(pdf, [])).to eq(0)
    expect(drawn_height(pdf, nil)).to eq(0)
  end

  it "keeps a full tier on one row and wraps twice that onto two" do
    three = drawn_height(document, Array.new(3) { |index| [ "Metric #{index}", "1" ] })
    six = drawn_height(document, Array.new(6) { |index| [ "Metric #{index}", "1" ] })

    # The trailing gap belongs to the strip, not to each tier, so it comes off both sides
    # before the tiers are compared: six metrics balance 3 + 3, never 4 + 2 or three tiers.
    gap = theme::SPACE[:lg]
    expect(six).to be > three
    expect(six - gap).to be_within(1).of((three - gap) * 2)
  end

  it "renders every metric when the count exceeds one tier" do
    pdf = document
    described_class.new(pdf: pdf).draw(
      [ [ "Room Revenue", "1" ], [ "Tax Revenue", "2" ], [ "Other Charges", "3" ],
        [ "Total Payments", "4" ], [ "Total Refunds", "5" ], [ "Total Adjustments", "6" ] ]
    )

    expect(extracted_text(pdf)).to include(
      "ROOM REVENUE", "TAX REVENUE", "OTHER CHARGES",
      "TOTAL PAYMENTS", "TOTAL REFUNDS", "TOTAL ADJUSTMENTS"
    )
  end

  it "draws a single metric at the same height as a full tier" do
    one = drawn_height(document, [ [ "Guest stays", "1,204" ] ])
    full = drawn_height(document, Array.new(3) { |index| [ "Metric #{index}", "1" ] })

    expect(one).to eq(full)
    expect(extracted_text(document.tap { |pdf| described_class.new(pdf: pdf).draw([ [ "Guest stays", "1,204" ] ]) })).to include("GUEST STAYS", "1,204")
  end

  it "fits four columns on a landscape sheet and three in portrait" do
    landscape = drawn_height(document(page_layout: :landscape), Array.new(4) { |index| [ "Metric #{index}", "1" ] })
    portrait = drawn_height(document, Array.new(4) { |index| [ "Metric #{index}", "1" ] })

    gap = theme::SPACE[:lg]
    expect(landscape - gap).to be_within(1).of((portrait - gap) / 2)
  end

  it "holds a seven-figure money value on one line at every column count" do
    %i[portrait landscape].each do |layout|
      short = drawn_height(document(page_layout: layout), Array.new(4) { [ "Total", "1" ] })
      money = drawn_height(document(page_layout: layout), Array.new(4) { [ "Total", "MYR 1,204,567.89" ] })

      expect(money).to eq(short), "#{layout}: a money value wrapped where a short one did not"
    end
  end

  it "wraps a long label rather than shrinking it" do
    short = drawn_height(document, Array.new(3) { [ "Net", "1" ] })
    long = drawn_height(document, Array.new(3) { [ "Remaining Deposit Liability Carried Forward", "1" ] })

    expect(long).to be > short
  end

  it "moves a strip that does not fit onto the next page rather than splitting it" do
    pdf = document
    pdf.move_cursor_to 20
    described_class.new(pdf: pdf).draw([ [ "Records", "12" ] ])

    reader = PDF::Reader.new(StringIO.new(pdf.render))
    expect(reader.page_count).to eq(2)
    expect(reader.pages.last.text).to include("RECORDS", "12")
    expect(reader.pages.first.text).not_to include("RECORDS")
  end

  it "leaves ink as the fill colour for whatever is drawn next" do
    pdf = document
    described_class.new(pdf: pdf).draw([ [ "Records", "12" ] ])

    expect(pdf.fill_color).to eq(theme::COLORS[:ink])
  end
end
