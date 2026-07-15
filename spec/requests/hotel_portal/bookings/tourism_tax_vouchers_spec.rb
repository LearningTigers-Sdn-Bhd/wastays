# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::TourismTaxVouchers", type: :request do
  let(:hotel) { create(:hotel, tourism_tax_enabled: true, tourism_tax_amount: 10.0) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_country: "Singapore",
      tourism_tax_amount: 10.0,
      tax_lines: [ { "type" => "tourism_tax", "amount" => 10.0 } ])
  end

  before do
    permission = Permission.find_or_create_by!(slug: "manage_bookings") { |entry| entry.name = "Manage Bookings" }
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "POST /hotel/:hotel_id/bookings/:booking_id/tourism_tax_voucher/issue" do
    it "issues voucher before tourism tax has been collected" do
      post issue_hotel_booking_tourism_tax_voucher_path(hotel, booking)

      expect(response).to redirect_to(hotel_booking_tourism_tax_voucher_path(hotel, booking))
      expect(booking.reload.tourism_tax_voucher_number).to be_present
    end

    it "assigns a stable sequential voucher number on first print" do
      post issue_hotel_booking_tourism_tax_voucher_path(hotel, booking)
      first_number = booking.reload.tourism_tax_voucher_number

      expect(first_number).to be_present

      post issue_hotel_booking_tourism_tax_voucher_path(hotel, booking)

      expect(booking.reload.tourism_tax_voucher_number).to eq(first_number)
    end

    it "records immutable audit details when first issuing voucher number" do
      expect {
        post issue_hotel_booking_tourism_tax_voucher_path(hotel, booking)
      }.to change(BookingAuditLog, :count).by(1)

      audit_log = BookingAuditLog.last
      expect(audit_log).to have_attributes(
        auditable: booking,
        user: user,
        action_type: "tourism_tax_voucher_issued",
        category: "financial",
        source: "staff"
      )
      expect(audit_log.new_value).to include("tourism_tax_voucher_number" => booking.reload.tourism_tax_voucher_number)
    end

    it "rejects booking with no tourism tax obligation" do
      booking.update!(guest_country: "Malaysia", tourism_tax_amount: 0, tax_lines: [])

      post issue_hotel_booking_tourism_tax_voucher_path(hotel, booking)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to eq("This booking has no tourism tax obligation.")
    end
  end

  describe "GET /hotel/:hotel_id/bookings/:booking_id/tourism_tax_voucher" do
    it "returns a PDF after tourism tax was collected and issued" do
      booking.update!(tourism_tax_collected: true)
      post issue_hotel_booking_tourism_tax_voucher_path(hotel, booking)

      get hotel_booking_tourism_tax_voucher_path(hotel, booking)
      pages = PDF::Reader.new(StringIO.new(response.body)).pages

      expect(response).to have_http_status(:success)
      expect(response.content_type).to eq("application/pdf")
      expect(pages.size).to eq(2)
      expect(pages.first.text).to include("VOUCHER", "COLLECTED", "Guest Signature", "Authorized Signatory", "This voucher is to prove that the guest has paid the tourism fee.")
      expect(pages.last.text).to include("VOUCHER - DUPLICATE COPY", "COLLECTED", "Guest Signature", "Authorized Signatory", "This voucher is to prove that the guest has paid the tourism fee.")
    end

    it "does not issue voucher number on PDF GET" do
      get hotel_booking_tourism_tax_voucher_path(hotel, booking)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(booking.reload.tourism_tax_voucher_number).to be_nil
    end

    it "labels uncollected voucher as payable" do
      post issue_hotel_booking_tourism_tax_voucher_path(hotel, booking)
      get hotel_booking_tourism_tax_voucher_path(hotel, booking)
      text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")

      expect(text).to include("This voucher records the tourism fee payable for this stay.")
      expect(text).not_to include("This voucher is to prove that the guest has paid the tourism fee.")
    end

    it "denies access to staff without manage_bookings permission" do
      staff = create(:user)
      other_role = create(:role, account: hotel.account)
      create(:user_hotel_access, user: staff, hotel: hotel, role: other_role)
      sign_in_as(staff)

      post issue_hotel_booking_tourism_tax_voucher_path(hotel, booking)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end

    it "does not expose another hotel's booking" do
      other_booking = create(:booking, guest_country: "Singapore", tourism_tax_amount: 10.0, tax_lines: [ { "type" => "tourism_tax", "amount" => 10.0 } ])

      post issue_hotel_booking_tourism_tax_voucher_path(hotel, other_booking)

      expect(response).to have_http_status(:not_found)
      expect(other_booking.reload.tourism_tax_voucher_number).to be_nil
    end
  end
end
