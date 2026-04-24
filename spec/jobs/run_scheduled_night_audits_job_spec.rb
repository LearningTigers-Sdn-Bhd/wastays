require "rails_helper"

RSpec.describe RunScheduledNightAuditsJob, type: :job do
  let(:business_date) { Date.new(2026, 4, 23) }

  it "runs only for approved and live hotels using yesterday's business date" do
    approved_hotel = create(:hotel, status: "approved")
    live_hotel = create(:hotel, status: "live")
    create(:hotel, status: "registered")

    runner = instance_double(HotelOps::RunNightAudit, call: true)
    allow(HotelOps::RunNightAudit).to receive(:new).and_return(runner)

    described_class.perform_now(business_date)

    expect(HotelOps::RunNightAudit).to have_received(:new).with(
      hotel: approved_hotel,
      business_date: business_date,
      performed_by_user: nil,
      trigger_mode: "scheduled"
    )
    expect(HotelOps::RunNightAudit).to have_received(:new).with(
      hotel: live_hotel,
      business_date: business_date,
      performed_by_user: nil,
      trigger_mode: "scheduled"
    )
    expect(HotelOps::RunNightAudit).to have_received(:new).twice
  end

  it "continues when one hotel raises" do
    failing_hotel = create(:hotel, status: "approved")
    succeeding_hotel = create(:hotel, status: "live")

    allow(HotelOps::RunNightAudit).to receive(:new) do |hotel:, **|
      if hotel == failing_hotel
        instance_double(HotelOps::RunNightAudit).tap do |runner|
          allow(runner).to receive(:call).and_raise(StandardError, "boom")
        end
      else
        instance_double(HotelOps::RunNightAudit, call: true)
      end
    end

    expect { described_class.perform_now(business_date) }.not_to raise_error
    expect(HotelOps::RunNightAudit).to have_received(:new).twice
  end
end
