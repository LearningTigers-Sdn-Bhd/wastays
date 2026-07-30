require 'rails_helper'

RSpec.describe HotelPortal::RequestsArchive do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "John Doe", confirmation_token: "WS-1234") }

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

      row_ids = described_class.new(hotel).rows.map { |row| row[:request_id] }

      expect(row_ids).to include(long_ago_but_filed_recently.id)
    end

    it 'leaves out what was archived before the window' do
      filed_long_ago = create(:housekeeping_request, booking: booking, status: 'completed',
                              request_details: 'Filed long ago', archived_at: 20.days.ago)

      row_ids = described_class.new(hotel).rows.map { |row| row[:request_id] }

      expect(row_ids).not_to include(filed_long_ago.id)
    end

    it 'takes it in once the range is widened past it' do
      filed_long_ago = create(:housekeeping_request, booking: booking, status: 'completed',
                              request_details: 'Filed long ago', archived_at: 20.days.ago)

      row_ids = described_class.new(hotel, { days: '30' }).rows.map { |row| row[:request_id] }

      expect(row_ids).to include(filed_long_ago.id)
    end
  end

  describe '#rows' do
    it 'only returns archived requests' do
      archive = described_class.new(hotel)
      expect(archive.rows.size).to eq(3)
      row_keys = archive.rows.map { |row| [ row[:kind], row[:request_id] ] }
      expect(row_keys).not_to include([ "housekeeping", unarchived_request.id ])
    end

    context 'filtering by status' do
      it 'filters by pending status group' do
        archive = described_class.new(hotel, { status: 'pending' })
        expect(archive.rows.size).to eq(1)
        expect(archive.rows.first[:status]).to eq('pending')
      end

      it 'filters by completed status group' do
        archive = described_class.new(hotel, { status: 'completed' })
        expect(archive.rows.size).to eq(2) # completed housekeeping + resolved complaint
        statuses = archive.rows.map { |r| r[:status] }
        expect(statuses).to include('completed', 'resolved')
      end
    end

    context 'searching' do
      it 'searches by guest name' do
        archive = described_class.new(hotel, { q: 'John' })
        expect(archive.rows.size).to eq(3)
      end

      it 'searches by booking token' do
        archive = described_class.new(hotel, { q: '1234' })
        expect(archive.rows.size).to eq(3)
      end

      it 'searches by request details' do
        archive = described_class.new(hotel, { q: 'Towels' })
        expect(archive.rows.size).to eq(1)
        expect(archive.rows.first[:title]).to eq('2x Towels')
      end

      it 'searches by status group name "pending"' do
        archive = described_class.new(hotel, { q: 'pending' })
        expect(archive.rows.size).to eq(1)
        expect(archive.rows.first[:status]).to eq('pending')
      end

      it 'searches by status group name "completed"' do
        archive = described_class.new(hotel, { q: 'completed' })
        expect(archive.rows.size).to eq(2)
        statuses = archive.rows.map { |r| r[:status] }
        expect(statuses).to include('completed', 'resolved')
      end
    end

    context 'filtering by kind' do
      it 'filters by housekeeping' do
        archive = described_class.new(hotel, { kind: 'housekeeping' })
        expect(archive.rows.size).to eq(2)
      end

      it 'filters by complaint' do
        archive = described_class.new(hotel, { kind: 'complaint' })
        expect(archive.rows.size).to eq(1)
        expect(archive.rows.first[:kind]).to eq('complaint')
      end
    end
  end
end
