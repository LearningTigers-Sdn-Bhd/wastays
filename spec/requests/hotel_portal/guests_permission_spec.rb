require "rails_helper"

RSpec.describe "HotelPortal::Guests Permissions", type: :request do
  let!(:account) { create(:account) }
  let!(:plan) { create(:plan) }
  let!(:hotel) { create(:hotel, status: "approved", account: account, plan: plan) }
  let!(:user) { create(:user, account: account) }
  let!(:guest) { create(:guest, created_by_hotel: hotel) }

  before do
    create(:plan_feature, plan: plan, feature: create(:feature, slug: "unified_guest_profile"), enabled: true)
  end

  describe "DELETE /destroy" do
    context "when user has 'delete_guest_record' permission" do
      before do
        role = create(:role, account: account)
        role.permissions << (Permission.find_by(slug: 'delete_guest_record') || create(:permission, slug: 'delete_guest_record'))
        role.permissions << (Permission.find_by(slug: 'view_bookings') || create(:permission, slug: 'view_bookings'))
        UserHotelAccess.create!(user: user, hotel: hotel, role: role)
        sign_in_as(user)
      end

      it "successfully deletes the guest record" do
        delete hotel_guest_path(hotel, guest)
        expect(response).to have_http_status(:see_other)
        expect(Guest.exists?(guest.id)).to be_falsey
        expect(flash[:notice]).to include("successfully")
      end
    end

    context "when user only has 'manage_bookings' permission but not 'delete_guest_record'" do
      before do
        role = create(:role, account: account)
        role.permissions << (Permission.find_by(slug: 'manage_bookings') || create(:permission, slug: 'manage_bookings'))
        role.permissions << (Permission.find_by(slug: 'view_bookings') || create(:permission, slug: 'view_bookings'))
        UserHotelAccess.create!(user: user, hotel: hotel, role: role)
        sign_in_as(user)
      end

      it "denies access and does not delete the guest record" do
        delete hotel_guest_path(hotel, guest)
        # ApplicationController#user_not_authorized redirects to root_path or referrer
        expect(response).to have_http_status(:found)
        expect(Guest.exists?(guest.id)).to be_truthy
        expect(flash[:alert]).to include("not authorized")
      end
    end
  end
end
