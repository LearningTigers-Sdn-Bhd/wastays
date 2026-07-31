require 'rails_helper'

RSpec.describe HotelPortal::RequestsBoard do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "John Doe", confirmation_token: "WS-1234") }

  let!(:housekeeping_pending) do
    create(:housekeeping_request, booking: booking, status: 'pending', request_details: '2x Towels', archived_at: nil)
  end

  let!(:housekeeping_completed) do
    create(:housekeeping_request, booking: booking, status: 'completed', request_details: 'Bottle of water', completed_at: Time.current, archived_at: nil)
  end

  let!(:complaint_pending) do
    create(:complaint_request, booking: booking, status: 'pending', complaint_details: 'AC leaking', archived_at: nil)
  end

  let!(:archived_request) do
    create(:housekeeping_request, booking: booking, status: 'pending', archived_at: Time.current)
  end

  # The board shows outstanding work and what finished recently. What it costs
  # should follow how busy the hotel is now, not how long it has been open.
  describe 'what it loads' do
    def finished_history(hotel, bookings:)
      bookings.times do
        old_booking = create(:booking, hotel: hotel)
        create(:housekeeping_request, booking: old_booking, status: 'completed',
               requested_at: 200.days.ago, completed_at: 200.days.ago, archived_at: 200.days.ago)
        create(:complaint_request, booking: old_booking, status: 'resolved',
               requested_at: 200.days.ago, completed_at: 200.days.ago, archived_at: 200.days.ago)
        # A checkout is filed by when it was last written, having no archived_at
        # of its own, so history has to be old in that column too -- created now
        # it would be this week's archive, however long ago it was requested.
        create(:check_out_request, booking: old_booking, status: 'completed',
               requested_at: 200.days.ago, metadata: { 'archived_at' => 200.days.ago.iso8601 })
          .update_column(:updated_at, 200.days.ago)
      end
    end

    def queries_for(hotel)
      count = 0
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        count += 1 unless payload[:name].to_s.in?([ 'SCHEMA', 'TRANSACTION' ])
      end
      described_class.new(hotel).board_columns
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    def hotel_with_live_work
      live_hotel = create(:hotel)
      live_booking = create(:booking, hotel: live_hotel)
      create(:housekeeping_request, booking: live_booking, status: 'pending')
      create(:complaint_request, booking: live_booking, status: 'pending')
      create(:check_out_request, booking: live_booking, status: 'pending')
      live_hotel
    end

    it 'asks no more of a hotel with years behind it than of one without' do
      busy = hotel_with_live_work
      quiet = hotel_with_live_work
      finished_history(busy, bookings: 20)

      expect(queries_for(busy)).to eq(queries_for(quiet))
    end

    it 'leaves work finished long ago to the archive' do
      old_booking = create(:booking, hotel: hotel)
      long_done = create(:housekeeping_request, booking: old_booking, status: 'completed',
                         request_details: 'Ancient towels', requested_at: 200.days.ago,
                         completed_at: 200.days.ago, archived_at: nil)

      card_ids = described_class.new(hotel).board_columns.values.flatten.map { |card| card[:request_id] }

      expect(card_ids).not_to include(long_done.id)
    end

    it 'still shows work finished within the week' do
      recent = create(:housekeeping_request, booking: booking, status: 'completed',
                      request_details: 'Recent towels', completed_at: 2.days.ago, archived_at: nil)

      card_ids = described_class.new(hotel).board_columns[:completed].map { |card| card[:request_id] }

      expect(card_ids).to include(recent.id)
    end
  end

  describe 'reading a column a page at a time' do
    def walk(column, limit:)
      collected = []
      cursor = nil

      loop do
        page = described_class.new(hotel).page(column, cursor: cursor, limit: limit)
        collected.concat(page.cards.map { |card| [ card[:kind], card[:request_id] ] })
        cursor = page.next_cursor
        break if cursor.nil?
        raise 'paging did not terminate' if collected.size > 500
      end

      collected
    end

    it 'stops asking for more once the column is exhausted' do
      page = described_class.new(hotel).page(:complaint, limit: 25)

      expect(page.cards.size).to eq(1)
      expect(page).not_to be_more
      expect(page.next_cursor).to be_nil
    end

    it 'offers more while there is more' do
      12.times { create(:complaint_request, booking: booking, status: 'pending', archived_at: nil) }

      page = described_class.new(hotel).page(:complaint, limit: 5)

      expect(page.cards.size).to eq(5)
      expect(page).to be_more
    end

    it 'hands out every card exactly once' do
      12.times { |i| create(:complaint_request, booking: booking, status: 'pending', complaint_details: "Issue #{i}", archived_at: nil) }
      expected = ComplaintRequest.where(booking: booking).pluck(:id).sort

      collected = walk(:complaint, limit: 5)

      expect(collected.size).to eq(expected.size)
      expect(collected.uniq.size).to eq(collected.size)
      expect(collected.map(&:last).sort).to eq(expected)
    end

    # Three tables feed the completed column. Ids repeat across them, so rows
    # sharing an instant are exactly where a page boundary loses or repeats one.
    it 'hands out every card exactly once when three tables share an instant' do
      finished_at = 2.days.ago.change(usec: 0)
      6.times { create(:housekeeping_request, booking: booking, status: 'completed', completed_at: finished_at, archived_at: nil) }
      6.times { create(:complaint_request, booking: booking, status: 'resolved', completed_at: finished_at, archived_at: nil) }
      6.times { create(:check_out_request, booking: booking, status: 'completed', updated_at: finished_at) }

      collected = walk(:completed, limit: 4)

      expect(collected.uniq.size).to eq(collected.size)
      expect(collected.size).to eq(described_class.new(hotel).board_counts[:completed])
    end

    it 'counts the whole column, not the page of it' do
      12.times { create(:complaint_request, booking: booking, status: 'pending', archived_at: nil) }

      board = described_class.new(hotel)

      expect(board.page(:complaint, limit: 5).cards.size).to eq(5)
      expect(board.board_counts[:complaint]).to eq(13)
    end

    it 'starts at the beginning when handed a cursor it cannot read' do
      first = described_class.new(hotel).page(:complaint, limit: 5)

      expect(described_class.new(hotel).page(:complaint, cursor: nil, limit: 5).cards).to eq(first.cards)
    end
  end

  describe 'the date window' do
    it 'defaults to the past week' do
      expect(described_class.new(hotel).date_window.days).to eq(7)
    end

    # The window governs the lanes that grow without end. Open work is cleared by
    # staff rather than by time, so bounding it only ever hid it: on the narrowest
    # range a request from last week would have been unreachable, and the board
    # could do no more than say how many there were.
    it 'keeps outstanding work however long ago it was asked for' do
      stale = create(:housekeeping_request, booking: booking, status: 'pending',
                     request_details: 'Stale towels', requested_at: 200.days.ago, archived_at: nil)

      card_ids = described_class.new(hotel, { days: '1' }).board_columns[:housekeeping].map { |card| card[:request_id] }

      expect(card_ids).to include(stale.id)
    end

    it 'keeps an old open checkout and an old open complaint too' do
      complaint = create(:complaint_request, booking: booking, status: 'pending', requested_at: 90.days.ago, archived_at: nil)
      checkout = create(:check_out_request, booking: booking, status: 'pending', requested_at: 90.days.ago)

      board = described_class.new(hotel, { days: '1' })

      expect(board.board_columns[:complaint].map { |card| card[:request_id] }).to include(complaint.id)
      expect(board.board_columns[:checkout].map { |card| card[:request_id] }).to include(checkout.id)
    end

    it 'still bounds what has been finished' do
      long_done = create(:housekeeping_request, booking: booking, status: 'completed',
                         request_details: 'Done long ago', requested_at: 40.days.ago,
                         completed_at: 30.days.ago, archived_at: nil)

      card_ids = described_class.new(hotel).board_columns[:completed].map { |card| card[:request_id] }

      expect(card_ids).not_to include(long_done.id)
    end

    # Outstanding work is placed by when it was asked for, but finished work by
    # when it was finished -- otherwise closing something old drops it from the
    # completed column on the very day it was closed.
    it 'shows work requested before the window but finished inside it' do
      long_running = create(:housekeeping_request, booking: booking, status: 'completed',
                            request_details: 'Long running job', requested_at: 40.days.ago,
                            completed_at: 1.day.ago, archived_at: nil)

      card_ids = described_class.new(hotel).board_columns[:completed].map { |card| card[:request_id] }

      expect(card_ids).to include(long_running.id)
    end

    # The anchor moves the window, and the window is the finished lanes.
    it 'follows the anchor date backwards through what was finished' do
      older = create(:housekeeping_request, booking: booking, status: 'completed',
                     request_details: 'Older towels', completed_at: 6.days.ago, archived_at: nil)
      recent = create(:housekeeping_request, booking: booking, status: 'completed',
                      request_details: 'Todays towels', completed_at: Time.current, archived_at: nil)

      board = described_class.new(hotel, { date: 5.days.ago.to_date.iso8601, days: '3' })
      ids = board.board_columns[:completed].map { |card| card[:request_id] }

      expect(ids).to include(older.id)
      expect(ids).not_to include(recent.id)
    end
  end

  describe '#board_columns' do
    # The board carries the archive as a column of its own now, so a spec about
    # the working columns has to say which ones it means.
    def open_cards(board)
      board.board_columns.except(:archived).values.flatten
    end

    it 'treats the All lane URL value as every column' do
      board = described_class.new(hotel, { lanes: [ 'all' ] })

      expect(board.visible_columns).to eq(described_class::COLUMNS)
    end

    it 'lets All win over any stale specific lane values in the URL' do
      board = described_class.new(hotel, { lanes: %w[all housekeeping] })

      expect(board.visible_columns).to eq(described_class::COLUMNS)
    end

    it 'keeps an archived request out of the working columns' do
      board = described_class.new(hotel)

      expect(open_cards(board).size).to eq(3)
      expect(open_cards(board).map { |c| [ c[:kind], c[:request_id] ] })
        .not_to include([ "housekeeping", archived_request.id ])
    end

    it 'shows it in the archive column instead' do
      board = described_class.new(hotel)

      expect(board.board_columns[:archived].map { |c| c[:request_id] }).to eq([ archived_request.id ])
    end

    it 'reads the archive column through the same filters as the rest' do
      board = described_class.new(hotel, { q: 'nothing matches this' })

      expect(board.board_columns[:archived]).to be_empty
    end

    context 'searching' do
      it 'searches by guest name' do
        board = described_class.new(hotel, { q: 'John' })
        total_cards = open_cards(board).size
        expect(total_cards).to eq(3)
      end

      it 'searches by request details' do
        board = described_class.new(hotel, { q: 'Towels' })
        total_cards = open_cards(board).size
        expect(total_cards).to eq(1)
        expect(board.board_columns[:housekeeping].first[:title]).to eq('2x Towels')
      end

      it 'keeps everything of a kind when the term names the kind' do
        board = described_class.new(hotel, { q: 'complaint' })

        expect(board.board_columns[:complaint].map { |c| c[:request_id] }).to include(complaint_pending.id)
        expect(board.board_columns[:housekeeping]).to be_empty
      end

      it 'searches by room number' do
        in_room = create(:housekeeping_request, booking: booking, status: 'pending',
                         request_details: 'Mini bar restock', room_number: '412', archived_at: nil)

        board = described_class.new(hotel, { q: '412' })

        expect(board.board_columns[:housekeeping].map { |c| c[:request_id] }).to eq([ in_room.id ])
      end

      it 'does not search the body of an internal note' do
        create(:housekeeping_request, booking: booking, status: 'pending',
               request_details: 'Nothing matching here', archived_at: nil,
               internal_notes: [ { 'body' => 'Guest was apologetic' } ])

        board = described_class.new(hotel, { q: 'apologetic' })

        expect(open_cards(board)).to be_empty
      end

      it 'searches by status group name "pending"' do
        board = described_class.new(hotel, { q: 'pending' })
        total_cards = open_cards(board).size
        expect(total_cards).to eq(2) # housekeeping pending + complaint pending
      end

      it 'searches by status group name "completed"' do
        board = described_class.new(hotel, { q: 'completed' })
        total_cards = open_cards(board).size
        expect(total_cards).to eq(1)
        expect(board.board_columns[:completed].first[:status]).to eq('completed')
      end
    end

    context 'filtering by status (hidden but logic exists)' do
      it 'filters by pending status group' do
        board = described_class.new(hotel, { status: 'pending' })
        total_cards = open_cards(board).size
        expect(total_cards).to eq(2)
      end

      it 'filters by completed status group' do
        board = described_class.new(hotel, { status: 'completed' })
        total_cards = open_cards(board).size
        expect(total_cards).to eq(1)
      end

      # A guest's request arrives as "pending" and reads "new" once a dispatcher
      # takes it. Both are still outstanding, so the filter has to find both.
      it 'keeps dispatched work in the pending status group' do
        dispatched = create(:housekeeping_request, booking: booking, status: 'new', request_details: 'Extra pillows', archived_at: nil)

        board = described_class.new(hotel, { status: 'pending' })

        expect(board.board_columns[:housekeeping].map { |c| c[:request_id] }).to include(dispatched.id)
      end

      it 'finds dispatched work when searching for pending' do
        dispatched = create(:housekeeping_request, booking: booking, status: 'assigned', request_details: 'Extra blanket', archived_at: nil)

        board = described_class.new(hotel, { q: 'pending' })

        expect(board.board_columns[:housekeeping].map { |c| c[:request_id] }).to include(dispatched.id)
      end
    end

    context 'checkout room cleaning tasks' do
      let!(:checkout_cleaning) do
        create(:housekeeping_request, booking: booking, status: 'new', request_details: 'Checkout Room Cleaning', archived_at: nil)
      end

      it 'groups checkout room cleaning under checkout column' do
        board = described_class.new(hotel)
        columns = board.board_columns
        expect(columns[:checkout].map { |c| c[:request_id] }).to include(checkout_cleaning.id)
        expect(columns[:housekeeping].map { |c| c[:request_id] }).not_to include(checkout_cleaning.id)
      end

      it 'shows one card when the cleaning names the checkout already on the board' do
        checkout_request = create(:check_out_request, booking: booking, status: 'pending')
        checkout_cleaning.update!(metadata: { 'checkout_request_id' => checkout_request.id })

        columns = described_class.new(hotel).board_columns

        expect(columns[:checkout].map { |c| c[:request_id] }).to contain_exactly(checkout_request.id)
        expect(columns.values.flatten.map { |c| c[:request_id] }).not_to include(checkout_cleaning.id)
      end

      it 'shows one card when a legacy cleaning shares its booking with a checkout on the board' do
        checkout_request = create(:check_out_request, booking: booking, status: 'pending')

        columns = described_class.new(hotel).board_columns

        expect(columns[:checkout].map { |c| c[:request_id] }).to contain_exactly(checkout_request.id)
      end

      it 'keeps a legacy cleaning when the checkout on the board belongs to another booking' do
        other_booking = create(:booking, hotel: hotel)
        checkout_request = create(:check_out_request, booking: other_booking, status: 'pending')

        columns = described_class.new(hotel).board_columns

        expect(columns[:checkout].map { |c| c[:request_id] }).to contain_exactly(checkout_request.id, checkout_cleaning.id)
      end

      it 'keeps a cleaning whose named checkout is not on the board' do
        checkout_request = create(:check_out_request, booking: booking, status: 'completed', metadata: { 'archived_at' => Time.current.iso8601 })
        checkout_cleaning.update!(metadata: { 'checkout_request_id' => checkout_request.id })

        columns = described_class.new(hotel).board_columns

        expect(columns[:checkout].map { |c| c[:request_id] }).to contain_exactly(checkout_cleaning.id)
      end
    end

    context 'checkout requests' do
      let!(:checkout_request) do
        create(:check_out_request, booking: booking, status: 'pending', metadata: {})
      end

      it 'maps the checkout status to its workflow status' do
        card = described_class.new(hotel).board_columns[:checkout].find do |checkout_card|
          checkout_card[:request_id] == checkout_request.id
        end

        expect(card[:status]).to eq('new')
      end
    end
  end
end
