require "rails_helper"

RSpec.describe HotelOps::SeedAccountRoles do
  let(:account) { create(:account) }

  before do
    %w[manage_account manage_hotel_profile manage_room_types manage_rates manage_inventory view_bookings manage_bookings view_guest_phone manage_guest_arrival view_audit_logs export_audit_logs manage_users manage_night_audit].each do |slug|
      Permission.find_or_create_by!(slug: slug) do |permission|
        permission.name = slug.humanize
      end
    end
  end

  it "creates role templates and links existing permissions" do
    expect {
      described_class.call(account)
    }.to change { Role.where(account: account).count }.by(4)

    owner = Role.find_by!(account: account, slug: "hotel_owner")
    expect(owner.role_permissions).not_to be_empty
  end
end
