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
      document_type: 'PASSPORT',
      date_of_birth: '1990-05-20'
    }
  end

  describe '#call' do
    before do
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      room_code.update!(is_taxable: true)
      room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    end

    it 'creates booking, rooms, guest link, pre-checkin, and converts quote' do
      dispatcher = instance_double(Notifications::Dispatcher, call: [])
      allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)

      result = nil
      expect {
        result = described_class.new(quote_token: quote.token, payment_details: payment_details).call
        expect(result.success?).to be(true), result.message
      }.to have_enqueued_job(WebhookBroadcastJob).with('booking_confirmed', anything)

      expect(result.success?).to be(true), result.message
      booking = result.booking
      expect(booking).to be_persisted
      expect(booking.status).to eq('confirmed')
      expect(booking.payment_status).to eq('captured')
      expect(booking.total_amount).to eq(200.to_d)
      expect(booking.guest_gender).to eq('female')
      expect(booking.guest_document_type).to eq('passport')
      expect(booking.guest_country).to eq('Singapore')
      expect(booking.tourism_tax_applied).to be(true)
      expect(booking.tourism_tax_amount.to_f).to eq(10.0)

      expect(booking.booking_rooms.count).to eq(1)
      expect(booking.booking_rooms.first.room_type).to eq(room_type)
      expect(booking.booking_folio).to be_present
      expect(booking.booking_folio).to be_open

      expect(booking.pre_checkin).to be_present
      expect(booking.pre_checkin.status).to eq('pending')
      expect(booking.pre_checkin_status).to eq('pending')

      expect(booking.booking_guests.count).to eq(1)
      expect(booking.booking_guests.first.is_primary).to be(true)

      expect(quote.reload.status).to eq('converted')
      expect(Notifications::Dispatcher).to have_received(:new).with(event: :booking_confirmed, booking: booking)
    end

    it 'saves special requests to both booking and quote' do
      details = payment_details.merge(special_requests: 'Late arrival at 10 PM')

      result = described_class.new(quote_token: quote.token, payment_details: details).call

      expect(result.success?).to be(true)
      expect(result.booking.special_requests).to eq('Late arrival at 10 PM')
      expect(quote.reload.special_requests).to eq('Late arrival at 10 PM')
    end

    it 'returns existing booking when quote is already converted' do
      existing = create(:booking, booking_quote: quote, hotel: hotel)

      result = described_class.new(quote_token: quote.token, payment_details: payment_details).call

      expect(result.success?).to be(true), result.message
      expect(result.booking).to eq(existing)
      expect(Booking.where(booking_quote_id: quote.id).count).to eq(1)
      expect(existing.reload.booking_folio).to be_present
    end

    it "creates a folio while Night Audit is running without bypassing payment posting guards" do
      hotel.current_business_date_record.update!(status: "audit_running")

      result = described_class.new(quote_token: quote.token, payment_details: payment_details).call

      expect(result.success?).to be(true), result.message
      expect(result.booking.booking_folio).to be_present
    end

    it 'fails when the guest is blacklisted' do
      create(:guest, email: 'jane@example.com', blacklisted: true)

      result = described_class.new(quote_token: quote.token, payment_details: payment_details).call

      expect(result.success?).to be(false)
      expect(result.message).to eq('You are blacklisted from booking this hotel.')
    end

    it 'fails for expired quote' do
      quote.update!(status: 'expired')

      result = described_class.new(quote_token: quote.token, payment_details: payment_details).call

      expect(result.success?).to be(false)
      expect(result.message).to eq('Quote has expired.')
    end

    it 'expires and releases a stale active quote before confirmation' do
      quote.update!(expires_at: 1.minute.ago)
      create(:room_inventory, room_type: room_type, date: quote.check_in, quantity: 4, status: 'open')

      result = described_class.new(quote_token: quote.token, payment_details: payment_details).call

      expect(result.success?).to be(false)
      expect(result.message).to eq('Quote has expired.')
      expect(quote.reload.status).to eq('expired')
      expect(room_type.room_inventories.find_by(date: quote.check_in).quantity).to eq(5)
      expect(Booking.where(booking_quote_id: quote.id)).to be_empty
    end
  end
end
