# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::BookingPresenter do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  subject { described_class.new(booking, hotel) }

  describe "#pending_requests_count" do
    it "returns the total of pending housekeeping and complaint requests" do
      create(:housekeeping_request, booking: booking, status: "pending")
      create(:housekeeping_request, booking: booking, status: "completed")
      create(:complaint_request, booking: booking, status: "pending")
      create(:complaint_request, booking: booking, status: "resolved")

      expect(subject.pending_requests_count).to eq(2)
    end
  end

  describe "#housekeeping_requests" do
    it "returns active or cancelled housekeeping requests" do
      req1 = create(:housekeeping_request, booking: booking, status: "pending")
      req2 = create(:housekeeping_request, booking: booking, status: "cancelled")
      create(:housekeeping_request, booking: booking, status: "completed", archived_at: Time.current)

      expect(subject.housekeeping_requests).to contain_exactly(req1, req2)
    end
  end

  describe "#complaint_requests" do
    it "returns active or cancelled complaint requests" do
      req1 = create(:complaint_request, booking: booking, status: "pending")
      req2 = create(:complaint_request, booking: booking, status: "cancelled")
      create(:complaint_request, booking: booking, status: "resolved", archived_at: Time.current)

      expect(subject.complaint_requests).to contain_exactly(req1, req2)
    end
  end

  describe "#requires_backdated_checkin_reason?", frozen_time: Time.zone.local(2026, 5, 18, 14) do
    let(:check_in_date) { Date.new(2026, 5, 18) }
    let(:booking) { create(:booking, hotel: hotel, check_in: check_in_date) }

    it "returns true if the check-in accounting date is closed" do
      create(:night_audit, hotel: hotel, business_date: check_in_date, status: "completed")
      hotel.current_business_date_record.update!(business_date: check_in_date, status: "closed")
      expect(subject.requires_backdated_checkin_reason?).to be true
    end

    it "returns false if no completed night audit exists for the check-in date" do
      create(:night_audit, hotel: hotel, business_date: check_in_date, status: "pending")
      expect(subject.requires_backdated_checkin_reason?).to be false
    end

    it "returns false if no night audit exists for the check-in date" do
      expect(subject.requires_backdated_checkin_reason?).to be false
    end
  end

  describe "#checked_in_at_form_value past midnight" do
    let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur") }
    let(:arrival_date) { Date.new(2026, 8, 25) }
    let(:booking) { create(:booking, hotel: hotel, check_in: arrival_date, check_out: arrival_date + 2) }

    # 26 Aug 00:30 in Kuala Lumpur, while the hotel still trades 25 Aug.
    let(:after_midnight) { Time.utc(2026, 8, 25, 16, 30) }

    before { hotel.current_business_date_record.update!(business_date: arrival_date, status: "open") }

    it "falls back to the scheduled arrival while the arrival date stays open" do
      with_frozen_time(after_midnight) do
        expect(subject.checked_in_at_form_value).to start_with("2026-08-25T")
      end
    end

    it "names the open business date in the hint" do
      with_frozen_time(after_midnight) do
        expect(subject.check_in_business_date_hint).to eq("Posts to business date 25 Aug 2026.")
      end
    end

    it "keeps the clock when the arrival date is closed" do
      hotel.current_business_date_record.update!(status: "closed")
      create(:hotel_business_date, hotel: hotel, business_date: arrival_date + 1, status: "open")

      with_frozen_time(after_midnight) do
        expect(subject.checked_in_at_form_value).to eq("2026-08-26T00:30")
      end
    end

    it "keeps the clock for an arrival on the current calendar date" do
      booking.update!(check_in: Date.new(2026, 8, 26), check_out: Date.new(2026, 8, 28))

      with_frozen_time(after_midnight) do
        expect(subject.checked_in_at_form_value).to eq("2026-08-26T00:30")
      end
    end

    it "keeps a check-in that was already recorded" do
      booking.update!(checked_in_at: hotel.hotel_time_zone.parse("2026-08-25 22:15"))

      with_frozen_time(after_midnight) do
        expect(subject.checked_in_at_form_value).to eq("2026-08-25T22:15")
      end
    end
  end

  describe "guest record counts" do
    it "counts the primary booking guest and additional guest records" do
      create(:booking_guest, booking: booking, is_primary: false)

      expect(subject.registered_guest_count).to eq(2)
      expect(subject.missing_guest_record_count).to eq(0)
    end

    it "returns the occupancy gap without going below zero" do
      booking.update!(adults: 3, children: 1)

      expect(subject.missing_guest_record_count).to eq(3)

      4.times { create(:booking_guest, booking: booking, is_primary: false) }

      expect(described_class.new(booking.reload, hotel).missing_guest_record_count).to eq(0)
    end
  end

  describe "#reference_ids" do
    it "returns the booking's internal and channel references" do
      booking.update!(
        reservation_number: 12,
        guest_registration_number: 34,
        external_reference: "OTA-55",
        channel_manager_reference: "CM-66"
      )

      expect(subject.reference_ids).to include(
        [ "Confirmation", booking.confirmation_token ],
        [ "Reservation", booking.formatted_reservation_number ],
        [ "Guest Registration", booking.formatted_guest_registration_number ],
        [ "External", "OTA-55" ],
        [ "Channel Manager", "CM-66" ]
      )
    end
  end

  describe "security deposit helpers" do
    it "summarizes held security deposits separately from booking totals" do
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:deposit, booking: booking, hotel: hotel, amount: 200, status: "held")
      create(:deposit, booking: booking, hotel: hotel, amount: 50, status: "released")
      booking.update!(deposit_status: "held")

      expect(subject.security_deposit_status_label).to eq("Held")
      expect(subject.held_security_deposit_total).to eq(200.to_d)
      expect(subject.formatted_held_security_deposit_total).to eq("MYR 200.00")
    end

    it "defaults the security deposit status when not set" do
      expect(subject.security_deposit_status_label).to eq("Not Required")
      expect(subject.formatted_held_security_deposit_total).to eq("MYR 0.00")
    end
  end

  describe "front desk display" do
    it "uses semantic status token classes" do
      booking.update!(status: "confirmed")

      expect(subject.status_variant_class).to include("border-info/30", "bg-info/10", "text-info")
      expect(subject.status_variant_class).not_to match(/blue|green|amber|rose|red|orange|violet|emerald|yellow/)
    end

    it "formats reservation timestamps in hotel local time" do
      hotel.update!(time_zone: "Kuala Lumpur")
      booking.update!(created_at: Time.utc(2026, 7, 15, 18, 30))

      expect(subject.created_at_date).to include("16 Jul 2026")
    end

    it "uses hotel local time for transaction form defaults" do
      hotel.update!(time_zone: "Kuala Lumpur")

      with_frozen_time(Time.utc(2026, 7, 15, 18, 30)) do
        expect(subject.checked_in_at_form_value).to eq("2026-07-16T02:30")
        expect(subject.checked_out_at_form_value).to eq("2026-07-16T02:30")
      end
    end

    it "uses hotel local date for late checkout rates" do
      hotel.update!(time_zone: "Kuala Lumpur")
      room_type = create(:room_type, hotel:, base_price: 100)
      create(:booking_room, booking:, room_type:, subtotal: 100)
      create(:room_rate, room_type:, date: Date.new(2026, 7, 16), price: 250)

      with_frozen_time(Time.utc(2026, 7, 15, 18, 30)) do
        expect(subject.suggested_late_checkout_amount).to eq(250.to_d)
      end
    end
  end
end
