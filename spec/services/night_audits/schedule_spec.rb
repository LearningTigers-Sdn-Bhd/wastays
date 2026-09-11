# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::Schedule do
  let(:hotel) { create(:hotel, :without_current_business_date) }
  let(:business_date) { Date.current - 1.day }
  let(:user) { create(:user, account: hotel.account) }

  before { BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date) }

  it "keeps a blocked readiness snapshot in preparation without enqueueing" do
    create(:booking, hotel: hotel, status: "checked_in", check_in: business_date, check_out: business_date + 1.day, checked_in_at: Time.current)
    expect(NightAudits::PublishStaffNotification).to receive(:call).with(night_audit: instance_of(NightAudit))

    expect {
      @result = described_class.call(hotel: hotel, business_date: business_date, performed_by_user: user, trigger_mode: "manual")
    }.not_to have_enqueued_job(NightAudits::RunJob)

    expect(@result.enqueued).to be(false)
    expect(@result.night_audit).to be_preparing
    expect(hotel.current_business_date_record).to be_open
  end

  it "enqueues a clean prepared audit once" do
    result = nil
    expect {
      result = described_class.call(hotel: hotel, business_date: business_date, performed_by_user: user, trigger_mode: "manual")
    }.to have_enqueued_job(NightAudits::RunJob)

    expect(result.enqueued).to be(true)
    expect(result.night_audit).to be_pending
    expect(result.night_audit.performed_by_user).to eq(user)

    expect {
      duplicate = described_class.call(hotel: hotel, business_date: business_date, performed_by_user: user, trigger_mode: "manual")
      expect(duplicate.enqueued).to be(false)
    }.not_to have_enqueued_job(NightAudits::RunJob)
  end

  it "enqueues a new scheduled audit with preliminary blockers" do
    create(:booking, hotel:, status: "checked_in", check_in: business_date, check_out: business_date + 1.day, checked_in_at: Time.current)

    expect {
      @result = described_class.call(hotel:, business_date:, performed_by_user: nil, trigger_mode: "scheduled")
    }.to have_enqueued_job(NightAudits::RunJob)

    expect(@result.enqueued).to be(true)
    expect(@result.night_audit).to be_pending
  end

  it "does not re-enqueue a blocked scheduled audit while blockers remain" do
    create(:booking, hotel:, status: "checked_in", check_in: business_date, check_out: business_date + 1.day, checked_in_at: Time.current)
    create(:night_audit, hotel:, business_date:, status: "blocked", trigger_mode: "scheduled")
    hotel.current_business_date_record.update!(status: "audit_blocked")

    expect {
      @result = described_class.call(hotel:, business_date:, performed_by_user: nil, trigger_mode: "scheduled")
    }.not_to have_enqueued_job(NightAudits::RunJob)

    expect(@result.enqueued).to be(false)
    expect(@result.night_audit).to be_blocked
  end

  it "uses post-close blockers before retrying a failed scheduled audit" do
    booking = create(
      :booking,
      hotel:,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day,
      checked_in_at: Time.current
    )
    create(:booking_room, booking:, subtotal: 100.0)
    create(:booking_folio, hotel:, booking:)
    create(:night_audit, hotel:, business_date:, status: "failed", trigger_mode: "scheduled")
    hotel.current_business_date_record.update!(status: "audit_blocked")

    expect {
      @result = described_class.call(hotel:, business_date:, performed_by_user: nil, trigger_mode: "scheduled")
    }.not_to have_enqueued_job(NightAudits::RunJob)

    expect(@result.enqueued).to be(false)
    expect(@result.night_audit).to be_failed
    expect(@result.evaluation[:blocked_details]["missing_nightly_charges"]).to include(
      include("booking_id" => booking.id)
    )
  end

  it "does not let a scheduled pass take over a manually owned preparation" do
    audit = create(:night_audit, hotel:, business_date:, status: "preparing", trigger_mode: "manual", performed_by_user: user)

    expect {
      result = described_class.call(hotel:, business_date:, performed_by_user: nil, trigger_mode: "scheduled")
      expect(result.enqueued).to be(false)
    }.not_to have_enqueued_job(NightAudits::RunJob)

    expect(audit.reload).to have_attributes(status: "preparing", trigger_mode: "manual", performed_by_user: user)
  end

  it "never invokes booking detection during a scheduled readiness check" do
    expect(NightAudits::DetectDueOuts).not_to receive(:call)
    expect(NightAudits::DetectMissedArrivals).not_to receive(:call)

    described_class.call(hotel:, business_date:, performed_by_user: nil, trigger_mode: "scheduled")
  end
end
