require 'rails_helper'

RSpec.describe HotelPortal::RequestsArchive do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "John Doe", confirmation_token: "WS-1234") }

  # The archive had a page of its own once and now has only a lane on the board,
  # so what the archive is gets asked for the way the only reader left asks for
  # it: the board, reading the sources this class describes.
  def archive_page(params = {}, cursor: nil, limit: HotelPortal::Requests::Paging::PAGE_SIZE)
    HotelPortal::RequestsBoard.new(hotel, params).page(:archived, cursor: cursor, limit: limit)
  end

  def rows_for(params = {}, cursor: nil)
    archive_page(params, cursor: cursor).cards
  end

  let!(:housekeeping_pending) do
    create(:housekeeping_request, booking: booking, status: 'pending', request_details: '2x Towels', archived_at: Time.current)
  end

  let!(:housekeeping_completed) do
    create(:housekeeping_request, booking: booking, status: 'completed', request_details: 'Bottle of water', archived_at: Time.current)
  end

  let!(:complaint_resolved) do
    create(:complaint_request, booking: booking, status: 'resolved', complaint_details: 'AC leaking', archived_at: Time.current)
  end

  let!(:unarchived_request) do
    create(:housekeeping_request, booking: booking, status: 'pending', archived_at: nil)
  end

  describe 'the date window' do
    it 'defaults to the past week' do
      expect(described_class.new(hotel).date_window.days).to eq(7)
    end

    # The archive is read by when something was put away, not by when it was
    # asked for -- an old request archived yesterday is yesterday's news.
    it 'reads by when a request was archived, not when it was requested' do
      long_ago_but_filed_recently = create(:housekeeping_request, booking: booking, status: 'completed',
                                           request_details: 'Old job, filed yesterday',
                                           requested_at: 90.days.ago, archived_at: 1.day.ago)

      expect(rows_for.map { |row| row[:request_id] }).to include(long_ago_but_filed_recently.id)
    end

    it 'leaves out what was archived before the window' do
      filed_long_ago = create(:housekeeping_request, booking: booking, status: 'completed',
                              request_details: 'Filed long ago', archived_at: 20.days.ago)

      expect(rows_for.map { |row| row[:request_id] }).not_to include(filed_long_ago.id)
    end

    it 'takes it in once the range is widened past it' do
      filed_long_ago = create(:housekeeping_request, booking: booking, status: 'completed',
                              request_details: 'Filed long ago', archived_at: 20.days.ago)

      expect(rows_for({ days: '30' }).map { |row| row[:request_id] }).to include(filed_long_ago.id)
    end
  end

  describe '#page' do
    it 'only returns archived requests' do
      rows = rows_for
      expect(rows.size).to eq(3)
      expect(rows.map { |row| [ row[:kind], row[:request_id] ] }).not_to include([ "housekeeping", unarchived_request.id ])
    end

    # The window is read against archived_at, so the page has to be ordered by it
    # too -- ordering by requested_at presented "archived this week" in the order
    # the requests were raised.
    it 'orders by when a request was put away, newest first' do
      filed_first = create(:housekeeping_request, booking: booking, status: 'completed',
                           request_details: 'Filed first', requested_at: 1.hour.ago, archived_at: 3.days.ago)
      filed_last = create(:housekeeping_request, booking: booking, status: 'completed',
                          request_details: 'Filed last', requested_at: 30.days.ago, archived_at: 1.minute.ago)

      ids = rows_for.map { |row| row[:request_id] }

      expect(ids.index(filed_last.id)).to be < ids.index(filed_first.id)
    end

    it 'reports a row by the timestamp its page is ordered by' do
      rows_for.each { |row| expect(row[:sort_at]).to be_present }
    end

    context 'filtering by status' do
      it 'filters by pending status group' do
        rows = rows_for({ status: 'pending' })
        expect(rows.size).to eq(1)
        expect(rows.first[:status]).to eq('pending')
      end

      it 'filters by completed status group' do
        rows = rows_for({ status: 'completed' })
        expect(rows.size).to eq(2) # completed housekeeping + resolved complaint
        expect(rows.map { |row| row[:status] }).to include('completed', 'resolved')
      end
    end

    context 'searching' do
      # The archive is where notes are read, so it is where they are searched.
      it 'searches the body of an internal note' do
        noted = create(:housekeeping_request, booking: booking, status: 'completed',
                       request_details: 'Nothing matching here', archived_at: Time.current,
                       internal_notes: [ { 'body' => 'Guest was apologetic' } ])

        expect(rows_for({ q: 'apologetic' }).map { |row| row[:request_id] }).to include(noted.id)
      end

      it 'keeps a kind out of the results when the filter rules it out' do
        expect(rows_for({ kind: 'complaint' }).map { |row| row[:kind] }.uniq).to eq([ 'complaint' ])
      end

      it 'searches by guest name' do
        expect(rows_for({ q: 'John' }).size).to eq(3)
      end

      it 'searches by booking token' do
        expect(rows_for({ q: '1234' }).size).to eq(3)
      end

      it 'searches by request details' do
        rows = rows_for({ q: 'Towels' })
        expect(rows.size).to eq(1)
        expect(rows.first[:title]).to eq('2x Towels')
      end

      it 'searches by status group name "pending"' do
        rows = rows_for({ q: 'pending' })
        expect(rows.size).to eq(1)
        expect(rows.first[:status]).to eq('pending')
      end

      it 'searches by status group name "completed"' do
        rows = rows_for({ q: 'completed' })
        expect(rows.size).to eq(2)
        expect(rows.map { |row| row[:status] }).to include('completed', 'resolved')
      end
    end

    context 'filtering by kind' do
      it 'filters by housekeeping' do
        expect(rows_for({ kind: 'housekeeping' }).size).to eq(2)
      end

      it 'filters by complaint' do
        rows = rows_for({ kind: 'complaint' })
        expect(rows.size).to eq(1)
        expect(rows.first[:kind]).to eq('complaint')
      end
    end

    context 'reading past the first page' do
      before do
        # Distinct archived_at values so the walk is not resting on the tiebreaker.
        6.times { |index| create(:complaint_request, booking: booking, status: 'resolved', complaint_details: "Filed #{index}", archived_at: (index + 1).hours.ago) }
      end

      it 'stops at the limit and says where it got to' do
        page = archive_page(limit: 4)

        expect(page.cards.size).to eq(4)
        expect(page).to be_more
        expect(page.next_cursor).to be_present
      end

      it 'shows each request once across the pages' do
        seen = []
        cursor = nil

        loop do
          page = archive_page(cursor: cursor, limit: 4)
          seen.concat(page.cards.map { |row| [ row[:kind], row[:request_id] ] })
          cursor = page.next_cursor
          break if cursor.nil?
        end

        expect(seen.size).to eq(9) # 3 from the setup + 6 here
        expect(seen.uniq.size).to eq(seen.size)
      end

      it 'says there is nothing more once the archive runs out' do
        page = archive_page(limit: 50)

        expect(page).not_to be_more
        expect(page.next_cursor).to be_nil
      end
    end
  end

  # A page of the archive used to be sliced out of every archived row in the
  # window, so a hotel with a long history paid for all of it to show 25 rows.
  # A page is now a page: what it loads follows the limit, not the archive.
  describe 'what a page loads' do
    def rows_loaded_for(hotel, limit:)
      count = 0
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        count += 1 unless payload[:name].to_s.in?([ 'SCHEMA', 'TRANSACTION' ])
      end
      HotelPortal::RequestsBoard.new(hotel).page(:archived, limit: limit)
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it 'asks no more of a deep archive than of a shallow one' do
      deep = create(:hotel)
      deep_booking = create(:booking, hotel: deep)
      40.times { |index| create(:housekeeping_request, booking: deep_booking, status: 'completed', archived_at: (index + 1).hours.ago) }

      shallow = create(:hotel)
      shallow_booking = create(:booking, hotel: shallow)
      create(:housekeeping_request, booking: shallow_booking, status: 'completed', archived_at: 1.hour.ago)

      expect(rows_loaded_for(deep, limit: 5)).to eq(rows_loaded_for(shallow, limit: 5))
    end

    it 'builds only the rows the page asked for' do
      40.times { |index| create(:complaint_request, booking: booking, status: 'resolved', archived_at: (index + 1).hours.ago) }

      expect(archive_page(limit: 5).cards.size).to eq(5)
    end
  end
end
