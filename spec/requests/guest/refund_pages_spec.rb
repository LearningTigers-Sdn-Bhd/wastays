require "rails_helper"

RSpec.describe "Guest refund pages", type: :request do
  let(:guest) { create(:guest) }
  let(:booking) { create(:booking, status: "confirmed", check_in: Date.current + 10.days, check_out: Date.current + 12.days) }

  before do
    create(:booking_guest, guest:, booking:, is_primary: true)
    create(:refund_policy, min_days_before_checkin: 3, refund_percentage: 80.0)
    otp = guest.generate_otp!
    post guest_login_path, params: { phone: guest.phone, otp: otp }
  end

  def document = Nokogiri::HTML(response.body)

  it "lists each request as a row and marks the active status chip" do
    refund_request = create(:refund_request, booking:, status: "pending")

    get guest_refund_requests_path, params: { status: "pending" }

    expect(document.css("turbo-frame#guest_refunds_results a.guest-card__row").map { |row| row["href"] })
      .to eq([ guest_refund_request_path(refund_request) ])
    expect(document.at_css("nav.guest-chips a[aria-current='page']").text).to eq("Pending")
  end

  it "points a guest with no refunds to their bookings" do
    get guest_refund_requests_path

    empty = document.at_css(".guest-empty-state")
    expect(empty.at_css(".guest-empty-state__title").text).to eq("No refund requests")
    expect(empty.at_css("a[href='#{guest_bookings_path}']").text.squish).to eq("View bookings")
  end

  it "builds the request form in GuestUI with a confirm on the submit" do
    get new_guest_booking_refund_request_path(booking, return_to: "details")

    expect(response).to have_http_status(:success)
    expect(document.at_css("fieldset.guest-fieldset legend").text).to eq("Bank details")
    expect(document.css("input[type='radio'][name='refund_request[account_type]']").map { |radio| radio["value"] })
      .to match_array(RefundRequest::ACCOUNT_TYPES)
    expect(document.at_css("select#refund_request_bank_name option[value='Maybank']")).to be_present
    expect(document.at_css("select#refund_request_bank_name option[value='#{BankCatalog::OTHER}']").text).to eq("Other bank")
    expect(document.at_css("input#refund_request_refund_amount")).to be_nil

    submit = document.at_css("form[action='#{guest_booking_refund_requests_path(booking)}'] button[type='submit']")
    expect(submit.text.squish).to eq("Submit Request and Cancel Booking")
    expect(submit["data-turbo-confirm"]).to include("cancels your booking")
    expect(document.at_css("a.guest-button[href='#{guest_booking_path(booking)}']").text.squish).to eq("Go Back")
  end

  describe "a guest in house" do
    let(:in_house) { create(:booking, status: "checked_in", check_in: Date.current, check_out: Date.current + 2.days) }

    before { create(:booking_guest, guest:, booking: in_house, is_primary: true) }

    it "offers a refund that keeps the stay on the booking page" do
      get guest_booking_path(in_house)

      link = document.css("a").find { |anchor| anchor.text.squish == "Ask for a refund" }
      expect(link["href"]).to eq(new_guest_booking_refund_request_path(in_house, return_to: "details"))
      expect(response.body).to include("This does not cancel your stay.")
    end

    it "asks for the amount and sends without a cancel confirm" do
      get new_guest_booking_refund_request_path(in_house)

      expect(document.at_css("input#refund_request_refund_amount")).to be_present
      submit = document.at_css("form[action='#{guest_booking_refund_requests_path(in_house)}'] button[type='submit']")
      expect(submit.text.squish).to eq("Send my request")
      expect(submit["data-turbo-confirm"]).to be_nil
    end

    it "files the request and leaves the stay checked in" do
      post guest_booking_refund_requests_path(in_house), params: {
        return_to: "details",
        refund_request: { refund_amount: "50", reason: "Air-conditioning broke", bank_name: BankCatalog::OTHER,
                          other_bank_name: "DBS Bank", account_holder_name: "Aisha", account_number: "1234",
                          account_type: "savings" }
      }

      expect(response).to redirect_to(guest_booking_path(in_house))
      expect(in_house.reload.status).to eq("checked_in")
      expect(in_house.refund_request).to have_attributes(refund_amount: 50, bank_name: "DBS Bank", status: "pending")
    end
  end
end
