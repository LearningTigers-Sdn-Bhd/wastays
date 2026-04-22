require 'rails_helper'

RSpec.describe BookingEngine::ConfirmBooking do
  let(:hotel) do
    create(:hotel, status: 'approved', tourism_tax_enabled: true, tourism_tax_amount: 10.0)
  end
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:quote) do
    create(
      :booking_quote,
      hotel: hotel,
      status: 'active',
      total_amount: 200.0,
      check_in: Date.current,
      check_out: Date.current + 1,
      adults: 2,
      children: 0,
      currency: 'MYR',
      hotel_snapshot: { 'name' => hotel.name },
      cancellation_policy_snapshot: 'Free cancellation'
    )
  end
  let!(:quote_item) { create(:booking_quote_item, booking_quote: quote, room_type: room_type, subtotal: 200.0) }

  let(:payment_details) do
    {
      guest_name: 'Jane Doe',
      guest_email: 'jane@example.com',
      guest_phone: '+60123456789',
      government_id: 'A1234567',
      gender: 'FEMALE',
      country: 'Singapore',
      document_type: 'PASSPORT'
    }
  end

  describe '#call' do
    it 'creates booking, rooms, guest link, pre-checkin, and converts quote' do
      result = described_class.new(quote_token: quote.token, payment_details: payment_details).call

      expect(result.success?).to be(true)
      booking = result.booking
      expect(booking).to be_persisted
      expect(booking.status).to eq('confirmed')
      expect(booking.payment_status).to eq('captured')
      expect(booking.guest_gender).to eq('female')
      expect(booking.guest_document_type).to eq('passport')
      expect(booking.guest_country).to eq('Singapore')
      expect(booking.tourism_tax_applied).to be(true)
      expect(booking.tourism_tax_amount.to_f).to eq(10.0)

      expect(booking.booking_rooms.count).to eq(1)
      expect(booking.booking_rooms.first.room_type).to eq(room_type)

      expect(booking.pre_checkin).to be_present
      expect(booking.pre_checkin.status).to eq('pending')
      expect(booking.pre_checkin_status).to eq('pending')

      expect(booking.booking_guests.count).to eq(1)
      expect(booking.booking_guests.first.is_primary).to be(true)

      expect(quote.reload.status).to eq('converted')
    end

    it 'returns existing booking when quote is already converted' do
      existing = create(:booking, booking_quote: quote, hotel: hotel)

      result = described_class.new(quote_token: quote.token, payment_details: payment_details).call

      expect(result.success?).to be(true)
      expect(result.booking).to eq(existing)
      expect(Booking.where(booking_quote_id: quote.id).count).to eq(1)
    end

    it 'fails for expired quote' do
      quote.update!(status: 'expired')

      result = described_class.new(quote_token: quote.token, payment_details: payment_details).call

      expect(result.success?).to be(false)
      expect(result.message).to eq('Quote has expired.')
    end
  end
end
