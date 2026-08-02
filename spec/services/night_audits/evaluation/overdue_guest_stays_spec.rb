require "rails_helper"

RSpec.describe NightAudits::Evaluation::OverdueGuestStays do
  let(:business_date) { Date.new(2026, 8, 1) }
  let(:hotel) do
    create(
      :hotel,
      accounting_business_date: business_date,
      time_zone: "Kuala Lumpur",
      business_starts_at: "08:00",
      business_ends_at: "02:00"
    )
  end
  let(:zone) { hotel.hotel_time_zone }
  let(:context) do
    NightAudits::Evaluation::Context.new(hotel: hotel, business_date: business_date, phase: :pre_close)
  end

  describe "#due_outs" do
    it "returns active stays whose checkout is before the next calendar day" do
      due_out = create(:booking,
        hotel: hotel,
        status: "checked_in",
        check_in: zone.local(2026, 7, 31, 15, 0),
        check_out: zone.local(2026, 8, 1, 11, 0))
      checkout_required = create(:booking,
        hotel: hotel,
        status: "checkout_required",
        check_in: zone.local(2026, 7, 31, 15, 0),
        check_out: zone.local(2026, 8, 1, 12, 0))
      create(:booking,
        hotel: hotel,
        status: "checked_in",
        check_in: zone.local(2026, 8, 1, 15, 0),
        check_out: zone.local(2026, 8, 2, 11, 0))

      expect(described_class.new(context: context).due_outs.map(&:id))
        .to contain_exactly(due_out.id, checkout_required.id)
    end
  end

  describe "#missed_arrivals" do
    it "combines eligible confirmed arrivals with existing detections" do
      confirmed = create(:booking,
        hotel: hotel,
        status: "confirmed",
        check_in: zone.local(2026, 8, 1, 15, 0),
        check_out: zone.local(2026, 8, 2, 11, 0))
      detected = create(:booking,
        hotel: hotel,
        status: "no_show_detected",
        no_show_detected_business_date: business_date,
        check_in: zone.local(2026, 8, 1, 16, 0),
        check_out: zone.local(2026, 8, 2, 12, 0))

      with_frozen_time(zone.local(2026, 8, 2, 3, 0)) do
        expect(described_class.new(context: context).missed_arrivals.map(&:id))
          .to contain_exactly(confirmed.id, detected.id)
      end
    end

    it "does not classify confirmed arrivals before the business date is closable" do
      confirmed = create(:booking,
        hotel: hotel,
        status: "confirmed",
        check_in: zone.local(2026, 8, 1, 15, 0),
        check_out: zone.local(2026, 8, 2, 11, 0))

      with_frozen_time(zone.local(2026, 8, 1, 20, 0)) do
        expect(described_class.new(context: context).missed_arrivals.map(&:id)).not_to include(confirmed.id)
      end
    end

    it "honors a completed pre-check-in arrival grace period" do
      hotel.update!(arrival_grace_period: 2.hours.to_i)
      confirmed = create(:booking,
        hotel: hotel,
        status: "confirmed",
        check_in: zone.local(2026, 8, 1, 15, 0),
        check_out: zone.local(2026, 8, 2, 11, 0))
      create(:pre_checkin,
        booking: confirmed,
        status: "completed",
        completed_at: zone.local(2026, 8, 1, 12, 0),
        metadata: { "estimated_arrival_time" => "01:30" })

      with_frozen_time(zone.local(2026, 8, 2, 2, 30)) do
        expect(described_class.new(context: context).missed_arrivals).to be_empty
      end

      with_frozen_time(zone.local(2026, 8, 2, 3, 31)) do
        expect(described_class.new(context: context).missed_arrivals.map(&:id)).to contain_exactly(confirmed.id)
      end
    end
  end
end
