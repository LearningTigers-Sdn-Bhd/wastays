require 'rails_helper'

RSpec.describe NightAudits::Evaluate do
  let(:hotel) { create(:hotel) }
  let(:business_date) { Date.current - 1.day }
  let(:service) { described_class.new(hotel: hotel, business_date: business_date) }

  describe '#call' do
    it 'returns a hash with blocked_details, exceptions, and summary' do
      result = service.call
      expect(result).to have_key(:blocked_details)
      expect(result).to have_key(:exceptions)
      expect(result).to have_key(:summary)
    end

    it 'identifies stale checked-in due outs as blockers' do
      create(:booking, status: 'checked_in', hotel: hotel, check_out: business_date)
      result = service.call
      expect(result[:blocked_details]["due_out_not_checked_out"]).not_to be_empty
    end

    it 'treats review_due_out bookings as warnings rather than blockers' do
      booking = create(:booking, status: 'review_due_out', hotel: hotel, check_in: business_date - 1.day, check_out: business_date)
      create(:booking_folio, booking: booking)

      result = service.call

      expect(result[:blocked_details]["due_out_not_checked_out"]).to be_empty
      expect(result[:exceptions]["review_due_out"].sole["booking_id"]).to eq(booking.id)
      expect(result[:exceptions]["review_due_out"].sole["reason"]).to eq("Due-out review carried forward")
    end

    it 'treats review_no_show bookings as warnings rather than blockers' do
      booking = create(:booking, status: 'review_no_show', hotel: hotel, check_in: business_date, check_out: business_date + 1.day, no_show_review_business_date: business_date)

      result = service.call

      expect(result[:exceptions]["review_no_show"].sole["booking_id"]).to eq(booking.id)
      expect(result[:blocked_details].values.flatten.pluck("booking_id")).not_to include(booking.id)
    end

    it 'treats checkout_required bookings as due-out blockers' do
      booking = create(:booking, status: 'checkout_required', hotel: hotel, check_out: business_date)

      result = service.call

      expect(result[:blocked_details]["due_out_not_checked_out"].sole["booking_id"]).to eq(booking.id)
    end

    it 'includes missing folios but omits missing nightly charges during pre-close evaluation' do
      booking = create(:booking,
        status: 'checked_in',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day,
        checked_in_at: business_date.beginning_of_day)
      create(:booking_room, booking: booking, subtotal: 120.0)

      result = described_class.new(hotel: hotel, business_date: business_date, phase: :pre_close).call

      expect(result[:blocked_details]["missing_folio"].sole["booking_id"]).to eq(booking.id)
      expect(result[:blocked_details]).not_to have_key("missing_nightly_charges")
    end

    it 'includes posting-generated blockers during post-close evaluation' do
      booking = create(:booking,
        status: 'checked_in',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day,
        checked_in_at: business_date.beginning_of_day)
      create(:booking_room, booking: booking, subtotal: 120.0)

      result = described_class.new(hotel: hotel, business_date: business_date, phase: :post_close).call

      expect(result[:blocked_details]["missing_folio"].first["booking_id"]).to eq(booking.id)
    end

    it 'keeps a missing folio as a blocker for a chargeable checked-in booking' do
      booking = create(:booking,
        status: 'checked_in',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day,
        checked_in_at: business_date.beginning_of_day)

      result = service.call

      expect(result[:blocked_details]["missing_folio"].sole["booking_id"]).to eq(booking.id)
      expect(result[:exceptions]).not_to have_key("missing_folio")
    end

    it 'keeps a missing folio as an accounting blocker after due-out review' do
      booking = create(:booking,
        status: 'review_due_out',
        hotel: hotel,
        check_in: business_date - 1.day,
        check_out: business_date)

      result = service.call

      expect(result[:blocked_details]["missing_folio"].sole["booking_id"]).to eq(booking.id)
      expect(result[:exceptions]["review_due_out"].sole["booking_id"]).to eq(booking.id)
    end

    it 'does not require a folio for proven non-chargeable bookings' do
      cancelled = create(:booking,
        status: 'cancelled',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day)
      no_show = create(:booking,
        status: 'no_show',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day)

      result = service.call

      missing_folio_ids = result[:blocked_details]["missing_folio"].pluck("booking_id")
      expect(missing_folio_ids).not_to include(cancelled.id, no_show.id)
    end

    it 'identifies large balance exceptions' do
      booking = create(:booking, status: 'checked_in', hotel: hotel)
      folio = create(:booking_folio, booking: booking)
      create(:folio_transaction, :charge, booking_folio: folio, amount: 2000, category: "other")

      result = service.call
      expect(result[:exceptions]["folio_balance_exceptions"]).not_to be_empty
      expect(result[:exceptions]["folio_balance_exceptions"].first["reason"]).to eq("Large outstanding balance")
    end
  end
end
