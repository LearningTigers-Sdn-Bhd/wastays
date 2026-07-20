require "rails_helper"

RSpec.describe HotelOps::SeedAccountRoles do
  let(:account) { create(:account) }

  before do
    %w[manage_account manage_hotel_profile manage_room_types manage_rates manage_inventory view_bookings view_financial_status manage_bookings view_guest_phone manage_guest_arrival view_audit_logs export_audit_logs manage_users manage_room_status post_charges post_folio_charges post_folio_payments execute_folio_refunds post_folio_adjustments post_folio_corrections post_folio_write_offs manage_folio_windows manage_folio_movements view_reports view_payouts manage_requests manage_night_audit].each do |slug|
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
    expect(owner.permissions.pluck(:slug)).to include(
      "post_folio_charges",
      "post_folio_payments",
      "execute_folio_refunds",
      "post_folio_adjustments",
      "post_folio_corrections",
      "post_folio_write_offs",
      "manage_folio_windows",
      "manage_folio_movements",
      "view_financial_status"
    )

    front_desk = Role.find_by!(account: account, slug: "front_desk")
    expect(front_desk.permissions.pluck(:slug)).to include("post_folio_charges", "post_folio_payments", "view_financial_status")
    expect(front_desk.permissions.pluck(:slug)).not_to include("execute_folio_refunds", "post_folio_write_offs", "post_folio_corrections", "manage_folio_windows", "manage_folio_movements")
  end
end
