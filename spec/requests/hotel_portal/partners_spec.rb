require 'rails_helper'

RSpec.describe "HotelPortal::Partners", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, role: "superadmin", password: "password") }
  let(:partner) { create(:partner, hotel: hotel) }

  before do
    user.user_hotel_accesses.create!(hotel: hotel, role: create(:role, name: "Admin"))
    sign_in_as user
  end

  describe "DELETE /hotel_portal/hotels/:hotel_id/partners/:id" do
    it "successfully deletes a partner with no associations" do
      partner_to_delete = create(:partner, hotel: hotel)
      expect {
        delete hotel_partner_path(hotel, partner_to_delete)
      }.to change(Partner, :count).by(-1)
      expect(response).to redirect_to(hotel_inventory_index_path(hotel, tab: "advanced", subtab: "partners"))
    end

    it "nullifies associations and deletes the partner when associations exist" do
      create(:booking, hotel: hotel, partner: partner)
      create(:booking_quote, hotel: hotel, partner: partner)

      expect {
        delete hotel_partner_path(hotel, partner)
      }.to change(Partner, :count).by(-1)

      expect(Booking.last.partner_id).to be_nil
      expect(BookingQuote.last.partner_id).to be_nil
    end
  end
end
