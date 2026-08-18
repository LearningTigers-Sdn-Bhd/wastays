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
      expect(pages.first.text).to include("TOURISM TAX VOUCHER", "GUEST COPY", "COLLECTED", "GUEST SIGNATURE", "AUTHORISED SIGNATURE")
      expect(pages.last.text).to include("TOURISM TAX VOUCHER", "HOTEL COPY", "COLLECTED")
    end

    # Tourism tax is charged per room per night. The voucher used to print the room count
    # as its quantity and the total divided by it as its rate, so a three-night stay
    # claimed a unit rate of thirty ringgit.
    it "prints room-nights as the quantity and the true per-room-night rate" do
      booking.update!(
        check_out: booking.check_in + 3.days,
        tourism_tax_amount: 30.0,
        tax_posting_snapshot: three_night_tourism_tax_snapshot(booking.check_in.to_date)
      )
      post issue_hotel_booking_tourism_tax_voucher_path(hotel, booking)

      get hotel_booking_tourism_tax_voucher_path(hotel, booking)
      text = PDF::Reader.new(StringIO.new(response.body)).pages.first.text

      expect(text).to include("Room nights")
      expect(text).to match(/Tourism tax\s+3\s+10\.00\s+30\.00/)
      expect(text).not_to include("30.00 30.00")
    end

    it "prints the hotel's tourism tax registration number and the guest's nationality" do
      hotel.update!(tourism_tax_registration_number: "TTX-998877")
      post issue_hotel_booking_tourism_tax_voucher_path(hotel, booking)

      get hotel_booking_tourism_tax_voucher_path(hotel, booking)
      text = PDF::Reader.new(StringIO.new(response.body)).pages.first.text

      expect(text).to include("Tourism Tax: TTX-998877")
      expect(text).to include("Nationality", "Singapore")
    end

    # The old voucher matched only the check-in posting source, so a tax taken anywhere
    # else printed "pending collection" beside a badge that said collected.
    it "dates a collection that was not taken at check-in" do
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction,
        booking_folio: folio,
        transaction_type: "payment",
        category: "cash",
        amount: 10.0,
        posting_date: Date.current,
        metadata: { "tourism_tax" => true, "source" => "tourism_tax_checkout" })
      booking.update!(tourism_tax_collected: true)
      post issue_hotel_booking_tourism_tax_voucher_path(hotel, booking)

      get hotel_booking_tourism_tax_voucher_path(hotel, booking)
      text = PDF::Reader.new(StringIO.new(response.body)).pages.first.text

      expect(text).to include(Date.current.strftime("%d %b %Y"))
      expect(text).not_to include("Not yet collected")
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

      expect(text).to include("Payable", "It is not evidence of payment.")
      expect(text).not_to include("evidence that the guest has paid")
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

  # One tourism tax line per stay date, each carrying the rate it was charged at and the
  # rooms it applied to — the shape Bookings::BuildFinancialSnapshot posts.
  def three_night_tourism_tax_snapshot(first_night)
    3.times.to_h do |offset|
      date = (first_night + offset.days).iso8601
      [
        date,
        [ {
          "type" => "tourism_tax", "primary_tax_key" => "tourism_tax", "name" => "Tourism Tax",
          "rate" => "10.0", "basis_amount" => 1, "amount" => "10.0",
          "currency" => "MYR", "stay_date" => date
        } ]
      ]
    end
  end
end
