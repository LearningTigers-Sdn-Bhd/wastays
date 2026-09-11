require "rails_helper"

RSpec.describe StaffNotification do
  it "supports active, unread, and recent staff feeds" do
    active = create(:staff_notification, created_at: 1.hour.ago)
    read = create(:staff_notification, hotel: active.hotel, subject: active.subject, read_at: Time.current)
    resolved = create(:staff_notification, hotel: active.hotel, subject: active.subject, resolved_at: Time.current)

    expect(described_class.active).to contain_exactly(active, read)
    expect(described_class.unread).to contain_exactly(active, resolved)
    expect(described_class.recent.first).to eq(resolved)
  end

  it "requires the subject to belong to the same hotel" do
    notification = build(:staff_notification, hotel: create(:hotel))

    expect(notification).not_to be_valid
    expect(notification.errors[:subject]).to include("must belong to the same hotel")
  end
end
