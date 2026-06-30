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

  describe "#requires_backdated_checkin_reason?" do
    let(:check_in_date) { Date.new(2026, 5, 18) }
    let(:booking) { create(:booking, hotel: hotel, check_in: check_in_date) }

    around { |example| travel_to(Time.zone.local(2026, 5, 18, 14, 0, 0)) { example.run } }

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
      create(:deposit, booking: booking, hotel: hotel, booking_folio: folio, amount: 200, status: "held")
      create(:deposit, booking: booking, hotel: hotel, booking_folio: folio, amount: 50, status: "released")
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
end
