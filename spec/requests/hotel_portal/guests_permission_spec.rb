# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Guests Permissions", type: :request do
  let!(:account) { create(:account) }
  let!(:plan) { create(:plan) }
  let!(:hotel) { create(:hotel, status: "live", account: account, plan: plan) }
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
        role.permissions << (Permission.find_by(slug: 'view_guest_records') || create(:permission, slug: 'view_guest_records'))
        UserHotelAccess.create!(user: user, hotel: hotel, role: role)
        sign_in_as(user)
      end

      it "successfully soft deletes the guest record even with active bookings" do
        create(:booking, hotel: hotel, status: "confirmed", guest_name: guest.name, guest_email: guest.email).tap do |b|
          create(:booking_guest, booking: b, guest: guest)
        end

        delete hotel_guest_path(hotel, guest)
        expect(response).to have_http_status(:see_other)

        # Verify it is hidden from normal queries but exists in DB
        expect(Guest.kept.exists?(guest.id)).to be_falsey
        expect(Guest.exists?(guest.id)).to be_truthy
        expect(Guest.find(guest.id).discarded?).to be_truthy
        expect(flash[:notice]).to include("successfully")
      end
    end

    context "when user only has 'manage_bookings' permission but not 'delete_guest_record'" do
      before do
        role = create(:role, account: account)
        role.permissions << (Permission.find_by(slug: 'manage_bookings') || create(:permission, slug: 'manage_bookings'))
        role.permissions << (Permission.find_by(slug: 'view_guest_records') || create(:permission, slug: 'view_guest_records'))
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

  describe "bulk status actions" do
    context "when the user can only view guest records" do
      before do
        role = create(:role, account: account)
        role.permissions << (Permission.find_by(slug: 'view_guest_records') || create(:permission, slug: 'view_guest_records'))
        UserHotelAccess.create!(user: user, hotel: hotel, role: role)
        sign_in_as(user)
      end

      it "denies every bulk status change" do
        params = { guest_ids: [ guest.id ].to_json, blacklist_reason: "Damage" }

        [ :bulk_vip, :bulk_unvip, :bulk_blacklist, :bulk_unblacklist ].each do |action|
          patch public_send("#{action}_hotel_guests_path", hotel), params: params

          expect(response).to have_http_status(:found)
          expect(flash[:alert]).to include("not authorized")
        end

        guest.reload
        expect(guest.vip_at?(hotel)).to be false
        expect(guest.blacklisted_at?(hotel)).to be false
      end

      it "denies a bulk delete" do
        delete bulk_destroy_hotel_guests_path(hotel), params: { guest_ids: [ guest.id ].to_json }

        expect(response).to have_http_status(:found)
        expect(guest.reload.discarded_at).to be_nil
      end
    end
  end
end
