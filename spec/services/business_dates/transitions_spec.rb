require "rails_helper"

RSpec.describe "BusinessDates transitions" do
  let(:hotel) { create(:hotel, :without_current_business_date) }
  let(:actor) { create(:user, :superadmin) }

  it "starts, blocks, and retries only through the strict state sequence" do
    record = create(:hotel_business_date, hotel: hotel, status: "open")

    expect(BusinessDates::StartAudit.call!(hotel: hotel, actor: actor)).to eq(record)
    expect(record.reload).to be_audit_running

    BusinessDates::BlockAudit.call!(hotel: hotel, actor: actor, blockers: { "x" => [ "y" ] })
    expect(record.reload).to be_audit_blocked
    expect(record.blockers_snapshot).to eq("x" => [ "y" ])

    BusinessDates::RetryAudit.call!(hotel: hotel, actor: actor)
    expect(record.reload).to be_audit_running
    expect(record.blockers_snapshot).to eq({})
  end

  it "rejects invalid transitions" do
    create(:hotel_business_date, hotel: hotel, status: "open")

    expect do
      BusinessDates::RetryAudit.call!(hotel: hotel, actor: actor)
    end.to raise_error(HotelBusinessDate::InvalidTransition, /expected audit_blocked/)
  end

  it "requires manage permission outside system context" do
    record = create(:hotel_business_date, hotel: hotel, status: "open")
    regular_user = create(:user)

    expect do
      BusinessDates::StartAudit.call!(hotel: hotel, actor: regular_user)
    end.to raise_error(HotelBusinessDate::InvalidTransition, /permission/)
    expect(record.reload).to be_open
  end

  it "atomically closes the current date and opens the next date" do
    record = create(:hotel_business_date, hotel: hotel, business_date: Date.current, status: "audit_running")

    result = BusinessDates::CloseAndOpenNext.call!(hotel: hotel, actor: actor)

    expect(result.closed_business_date.reload).to be_closed
    expect(result.next_business_date).to have_attributes(business_date: Date.current + 1.day, status: "open")
    expect(hotel.hotel_business_dates.current.count).to eq(1)
  end

  it "stores force-close accountability and opens the next date" do
    blockers = { "unresolved" => [ { "id" => 1 } ] }
    record = create(:hotel_business_date, hotel: hotel, business_date: Date.current, status: "audit_blocked", blockers_snapshot: blockers)

    result = BusinessDates::ForceClose.call!(
      hotel: hotel,
      actor: actor,
      reason: "Manager accepted unresolved blocker",
      blockers: blockers
    )

    expect(result.closed_business_date.reload).to have_attributes(
      status: "force_closed",
      force_closed_by: actor,
      force_close_reason: "Manager accepted unresolved blocker"
    )
    expect(result.closed_business_date.force_closed_at).to be_present
    expect(result.next_business_date).to be_open
  end

  it "rejects force close without a reason and forbids system force close" do
    create(:hotel_business_date, hotel: hotel, status: "audit_blocked")

    expect do
      BusinessDates::CloseAndOpenNext.call!(hotel: hotel, actor: actor, force: true)
    end.to raise_error(HotelBusinessDate::InvalidTransition, /reason/)

    expect do
      BusinessDates::CloseAndOpenNext.call!(hotel: hotel, force: true, reason: "Automated", system_context: true)
    end.to raise_error(HotelBusinessDate::InvalidTransition, /System context/)
  end

  it "resets authority atomically to one requested current date" do
    original = create(:hotel_business_date, hotel: hotel, status: "open")
    create(:hotel_business_date, hotel: hotel, business_date: original.business_date - 1.day, status: "closed")

    replacement = BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current + 3.days)

    expect(replacement).to have_attributes(business_date: Date.current + 3.days, status: "open")
    expect(hotel.hotel_business_dates.reload).to contain_exactly(replacement)
  end

  it "rolls back authority reset when replacement creation fails" do
    original = create(:hotel_business_date, hotel: hotel, status: "open")
    allow(HotelBusinessDate).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

    expect do
      BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current + 3.days)
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(hotel.hotel_business_dates.reload).to contain_exactly(original)
  end

  it "rolls back close when the next business date already exists" do
    record = create(:hotel_business_date, hotel: hotel, business_date: Date.current, status: "audit_running")
    create(:hotel_business_date, hotel: hotel, business_date: Date.current + 1.day, status: "closed")

    expect do
      BusinessDates::CloseAndOpenNext.call!(hotel: hotel, actor: actor)
    end.to raise_error(HotelBusinessDate::InvalidTransition, /already exists/)

    expect(record.reload).to be_audit_running
  end
end
