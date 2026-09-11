require "rails_helper"

RSpec.describe NightAudits::PublishStaffNotification do
  let(:hotel) { create(:hotel) }
  let(:permission) { Permission.find_or_create_by!(slug: "manage_night_audit") { |record| record.name = "Manage Night Audit" } }
  let(:role) { create(:role, account: hotel.account) }
  let(:recipient) { create(:user, account: hotel.account) }
  let(:audit) do
    create(
      :night_audit,
      hotel:,
      business_date: hotel.current_business_date,
      status: "blocked",
      blocked_details: { "missing_folio" => [ { "booking_id" => 1 } ] }
    )
  end

  before do
    role.permissions << permission
    create(:user_hotel_access, hotel:, user: recipient, role:)
  end

  it "publishes one notification per permitted active recipient" do
    other = create(:user, account: hotel.account)
    create(:user_hotel_access, hotel:, user: other, role: create(:role, account: hotel.account))

    expect { described_class.call(night_audit: audit) }.to change(StaffNotification, :count).by(1)

    notification = recipient.staff_notifications.sole
    expect(notification).to have_attributes(
      hotel: hotel,
      subject: audit,
      notification_type: "night_audit_action_required",
      severity: "warning",
      read_at: nil,
      resolved_at: nil
    )
  end

  it "publishes an action-required notification for a preparing audit with blockers" do
    audit.update!(status: "preparing")

    expect { described_class.call(night_audit: audit) }.to change(StaffNotification, :count).by(1)

    expect(recipient.staff_notifications.sole).to have_attributes(
      notification_type: "night_audit_action_required",
      severity: "warning"
    )
  end

  it "updates the existing notification and resets read state on failure" do
    described_class.call(night_audit: audit)
    notification = recipient.staff_notifications.sole
    notification.update!(read_at: Time.current)
    audit.update!(status: "failed")

    expect { described_class.call(night_audit: audit) }.not_to change(StaffNotification, :count)

    expect(notification.reload).to have_attributes(
      notification_type: "night_audit_failed",
      severity: "critical",
      read_at: nil
    )
  end

  it "keeps read state for an unchanged repeated publication" do
    described_class.call(night_audit: audit)
    notification = recipient.staff_notifications.sole
    notification.update!(read_at: Time.current)

    described_class.call(night_audit: audit)

    expect(notification.reload.read_at).to be_present
  end

  it "resets read state when new blockers arrive for the same audit" do
    described_class.call(night_audit: audit)
    notification = recipient.staff_notifications.sole
    notification.update!(read_at: Time.current)

    audit.update!(blocked_details: { "missing_folio" => [ { "booking_id" => 1 }, { "booking_id" => 2 } ] })
    described_class.call(night_audit: audit)

    expect(notification.reload.read_at).to be_nil
    expect(notification.metadata["blocker_count"]).to eq(2)
  end

  it "still notifies the other recipients when one save fails" do
    other = create(:user, account: hotel.account)
    create(:user_hotel_access, hotel:, user: other, role:)
    allow(StaffNotification).to receive(:find_or_initialize_by).and_wrap_original do |original, *args|
      record = original.call(*args)
      raise ActiveRecord::StatementInvalid, "boom" if record.deduplication_key.end_with?(recipient.id.to_s)

      record
    end

    expect { described_class.call(night_audit: audit) }.to change(StaffNotification, :count).by(1)

    expect(other.staff_notifications.count).to eq(1)
    expect(recipient.staff_notifications.count).to eq(0)
  end

  it "resolves active notifications when the audit completes" do
    described_class.call(night_audit: audit)
    audit.update!(status: "completed")

    described_class.call(night_audit: audit)

    expect(recipient.staff_notifications.sole).to be_resolved
  end
end
