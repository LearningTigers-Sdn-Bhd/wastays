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

  describe '#board_columns' do
    it 'only returns active (unarchived) requests' do
      board = described_class.new(hotel)
      columns = board.board_columns
      total_cards = columns.values.flatten.size
      expect(total_cards).to eq(3)
      expect(columns.values.flatten.map { |c| c[:request_id] }).not_to include(archived_request.id)
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
    end
  end
end
