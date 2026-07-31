# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Requests::Paging do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }

  # Mixed into a board, which supplies the sources and asks for a page. This is
  # the smallest thing shaped like one.
  let(:board_class) do
    Class.new do
      include HotelPortal::Requests::Paging

      def read(sources, cursor: nil, limit: HotelPortal::Requests::Paging::PAGE_SIZE)
        paged(sources, cursor: cursor, limit: limit)
      end
    end
  end

  def housekeeping_source(relation = HousekeepingRequest.all, name: "housekeeping")
    HotelPortal::Requests::Paging::Source.new(
      name: name,
      relation: relation,
      sort_column: :requested_at,
      builder: ->(record) {
        HotelPortal::Requests::Card.new(
          kind: "housekeeping", record_kind: "housekeeping", request_id: record.id,
          title: record.request_details, status: record.status,
          requested_at: record.requested_at, sort_at: record.requested_at
        )
      }
    )
  end

  def complaint_source
    HotelPortal::Requests::Paging::Source.new(
      name: "complaint",
      relation: ComplaintRequest.all,
      sort_column: :requested_at,
      builder: ->(record) {
        HotelPortal::Requests::Card.new(
          kind: "complaint", record_kind: "complaint", request_id: record.id,
          title: record.complaint_details, status: record.status,
          requested_at: record.requested_at, sort_at: record.requested_at
        )
      }
    )
  end

  def request_at(time, details: "Towels")
    create(:housekeeping_request, booking: booking, status: "new",
           request_details: details, requested_at: time)
  end

  it "reads newest first" do
    oldest = request_at(3.hours.ago)
    newest = request_at(1.hour.ago)
    middle = request_at(2.hours.ago)

    page = board_class.new.read([ housekeeping_source ])

    expect(page.cards.map(&:request_id)).to eq([ newest.id, middle.id, oldest.id ])
  end

  it "stops at the limit and says there is more" do
    3.times { |index| request_at(index.hours.ago) }

    page = board_class.new.read([ housekeeping_source ], limit: 2)

    expect(page.cards.size).to eq(2)
    expect(page).to be_more
    expect(page.next_cursor).to be_a(HotelPortal::Requests::Cursor)
  end

  it "says there is no more when the last row fits" do
    2.times { |index| request_at(index.hours.ago) }

    page = board_class.new.read([ housekeeping_source ], limit: 2)

    expect(page).not_to be_more
    expect(page.next_cursor).to be_nil
  end

  # The point of a cursor over an offset: rows finished and archived while
  # somebody scrolls must not make the next page skip or repeat.
  it "carries on after the cursor without repeating a row" do
    requests = 4.times.map { |index| request_at(index.hours.ago) }

    first = board_class.new.read([ housekeeping_source ], limit: 2)
    second = board_class.new.read([ housekeeping_source ], cursor: first.next_cursor, limit: 2)

    expect(first.cards.map(&:request_id)).to eq(requests.first(2).map(&:id))
    expect(second.cards.map(&:request_id)).to eq(requests.last(2).map(&:id))
    expect(first.cards.map(&:request_id) & second.cards.map(&:request_id)).to be_empty
  end

  # A list is drawn from more than one table, and the order has to be total
  # across all of them rather than per source.
  it "merges two sources into one order" do
    older_housekeeping = request_at(3.hours.ago)
    newer_complaint = create(:complaint_request, booking: booking, status: "pending",
                             complaint_details: "AC broken", requested_at: 1.hour.ago)

    page = board_class.new.read([ housekeeping_source, complaint_source ])

    expect(page.cards.map(&:request_id)).to eq([ newer_complaint.id, older_housekeeping.id ])
    expect(page.cards.map(&:kind)).to eq(%w[complaint housekeeping])
  end

  # Ids only tell rows apart within their own table, so the source has to sit
  # between the timestamp and the id for the order to be total.
  it "names the source on every row it built" do
    request_at(1.hour.ago)

    page = board_class.new.read([ housekeeping_source(name: "housekeeping") ])

    expect(page.cards.map(&:sort_source)).to all(eq("housekeeping"))
  end

  it "reads an empty source as an empty page" do
    page = board_class.new.read([ housekeeping_source ])

    expect(page.cards).to be_empty
    expect(page).not_to be_more
  end
end
