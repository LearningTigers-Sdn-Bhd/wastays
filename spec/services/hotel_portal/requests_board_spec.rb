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
        create(:check_out_request, booking: old_booking, status: 'completed',
               requested_at: 200.days.ago, metadata: { 'archived_at' => 200.days.ago.iso8601 })
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

  describe 'the date window' do
    it 'defaults to the past week' do
      expect(described_class.new(hotel).date_window.days).to eq(7)
    end

    it 'leaves out work asked for before the window' do
      stale = create(:housekeeping_request, booking: booking, status: 'pending',
                     request_details: 'Stale towels', requested_at: 20.days.ago, archived_at: nil)

      card_ids = described_class.new(hotel).board_columns.values.flatten.map { |card| card[:request_id] }

      expect(card_ids).not_to include(stale.id)
    end

    it 'takes in that work once the range is widened past it' do
      stale = create(:housekeeping_request, booking: booking, status: 'pending',
                     request_details: 'Stale towels', requested_at: 20.days.ago, archived_at: nil)

      card_ids = described_class.new(hotel, { days: '30' }).board_columns[:housekeeping].map { |card| card[:request_id] }

      expect(card_ids).to include(stale.id)
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

    it 'follows the anchor date backwards' do
      older = create(:housekeeping_request, booking: booking, status: 'pending',
                     request_details: 'Older towels', requested_at: 10.days.ago, archived_at: nil)

      board = described_class.new(hotel, { date: 8.days.ago.to_date.iso8601 })

      expect(board.board_columns[:housekeeping].map { |card| card[:request_id] }).to include(older.id)
      expect(board.board_columns[:housekeeping].map { |card| card[:request_id] }).not_to include(housekeeping_pending.id)
    end

    describe 'counting what it leaves out' do
      it 'counts outstanding work older than the window, per column' do
        create(:housekeeping_request, booking: booking, status: 'pending', requested_at: 20.days.ago, archived_at: nil)
        create(:housekeeping_request, booking: booking, status: 'new', requested_at: 30.days.ago, archived_at: nil)
        create(:complaint_request, booking: booking, status: 'pending', requested_at: 20.days.ago, archived_at: nil)
        create(:check_out_request, booking: booking, status: 'pending', requested_at: 20.days.ago)

        counts = described_class.new(hotel).older_open_counts

        expect(counts[:housekeeping]).to eq(2)
        expect(counts[:complaint]).to eq(1)
        expect(counts[:checkout]).to eq(1)
      end

      it 'does not count work that is already finished' do
        create(:housekeeping_request, booking: booking, status: 'completed', requested_at: 20.days.ago,
               completed_at: 20.days.ago, archived_at: nil)

        expect(described_class.new(hotel).older_open_counts[:housekeeping]).to eq(0)
      end

      it 'counts nothing when the window already reaches everything' do
        create(:housekeeping_request, booking: booking, status: 'pending', requested_at: 20.days.ago, archived_at: nil)

        expect(described_class.new(hotel, { days: '30' }).older_open_counts[:housekeeping]).to eq(0)
      end
    end
  end

  describe '#board_columns' do
    it 'only returns active (unarchived) requests' do
      board = described_class.new(hotel)
      columns = board.board_columns
      total_cards = columns.values.flatten.size
      expect(total_cards).to eq(3)
      card_keys = columns.values.flatten.map { |c| [ c[:kind], c[:request_id] ] }
      expect(card_keys).not_to include([ "housekeeping", archived_request.id ])
    end

    context 'searching' do
      it 'searches by guest name' do
        board = described_class.new(hotel, { q: 'John' })
        total_cards = board.board_columns.values.flatten.size
        expect(total_cards).to eq(3)
      end

      it 'searches by request details' do
        board = described_class.new(hotel, { q: 'Towels' })
        total_cards = board.board_columns.values.flatten.size
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

        expect(board.board_columns.values.flatten).to be_empty
      end

      it 'searches by status group name "pending"' do
        board = described_class.new(hotel, { q: 'pending' })
        total_cards = board.board_columns.values.flatten.size
        expect(total_cards).to eq(2) # housekeeping pending + complaint pending
      end

      it 'searches by status group name "completed"' do
        board = described_class.new(hotel, { q: 'completed' })
        total_cards = board.board_columns.values.flatten.size
        expect(total_cards).to eq(1)
        expect(board.board_columns[:completed].first[:status]).to eq('completed')
      end
    end

    context 'filtering by status (hidden but logic exists)' do
      it 'filters by pending status group' do
        board = described_class.new(hotel, { status: 'pending' })
        total_cards = board.board_columns.values.flatten.size
        expect(total_cards).to eq(2)
      end

      it 'filters by completed status group' do
        board = described_class.new(hotel, { status: 'completed' })
        total_cards = board.board_columns.values.flatten.size
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
