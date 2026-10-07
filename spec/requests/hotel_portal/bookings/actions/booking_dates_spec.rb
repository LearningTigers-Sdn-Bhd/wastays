# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions booking dates", frozen_time: :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:other_hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) do
    create(:room_type, hotel:, name: "Garden Suite", quantity: 3, room_number_mode: "custom", room_numbers: %w[101 102 103])
  end
  let(:rate_plan) { create(:rate_plan, room_type:, name: "Flexible Rate") }
  let(:booking) do
    create(
      :booking,
      hotel:,
      guest_name: "Ada Lovelace",
      status: "confirmed",
      check_in: Date.current,
      check_out: Date.current + 2.days
    ).tap do |record|
      create(:booking_room, booking: record, room_type:, rate_plan:, room_number: "101")
    end
  end

  def grant_permission(slug)
    permission = Permission.find_by(slug:) || create(:permission, slug:, name: slug.humanize)
    create(:role_permission, role:, permission:)
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel:, date: Date.current)
    grant_permission("manage_bookings")
    grant_permission("view_bookings")
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  it "renders the Dates Sheet in the requesting frame" do
    get hotel_booking_action_edit_dates_path(hotel, booking),
      headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    dialog = document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-dates-sheet")
    expect(dialog).to be_present
    expect(dialog.text).to include("Edit dates", "Current stay", "Stay dates", "Estimated value")
    expect(dialog.at_css("#booking_check_in")).to be_present
    expect(dialog.at_css("#booking_check_out")).to be_present
    expect(dialog.at_css("select#booking_room_number")).to be_nil
    expect(dialog.at_css("select#booking_rate_selection")).to be_nil
    expect(response.body).not_to include("offcanvas", "drawer")
  end

  it "updates stay dates and completes the requesting Sheet" do
    patch hotel_booking_action_edit_dates_path(hotel, booking), params: {
      return_to: hotel_stay_view_path(hotel),
      booking: { check_in: Date.current + 1.day, check_out: Date.current + 4.days }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_sheet"', 'target="booking_action_sheet"', hotel_stay_view_path(hotel))
    expect(booking.reload.check_in.to_date).to eq(Date.current + 1.day)
    expect(booking.check_out.to_date).to eq(Date.current + 4.days)
    expect(booking.booking_rooms.first.reload.room_number).to eq("101")
  end

  it "posts missing closed-night charges when staff save the corrected dates" do
    prepare_closed_night

    patch hotel_booking_action_edit_dates_path(hotel, booking), params: {
      booking: { check_in: Date.current - 1.day, check_out: Date.current }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_sheet"')
    expect(booking.reload.booking_folio.folio_transactions.charge.pluck(:posting_date)).to eq([ Date.current - 1.day ])
    expect(booking.booking_folio.folio_forecasted_charges.forecast).not_to exist
  end

  it "keeps the Sheet open and preserves the stay when an edit removes a posted closed night" do
    prepare_closed_night
    result = Bookings::UpdateStayService.new(booking: booking, user: user,
      params: { check_in: Date.current - 1.day, check_out: Date.current }).call
    expect(result).to be_success

    patch hotel_booking_action_edit_dates_path(hotel, booking), params: {
      booking: { check_in: Date.current, check_out: Date.current + 1.day }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Review charge correction", "Reason for correction", "An authorized manager must confirm this correction.")
    expect(response.body).not_to include("The stay dates could not be updated.")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("button[type='submit']")['disabled']).to be_present
    expect(response.body).not_to include('action="complete_sheet"')
    expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(Date.current - 1.day)
  end

  it "confirms the reviewed correction in the same Sheet" do
    prepare_posted_closed_night
    grant_permission("manage_night_audit")
    grant_permission("override_financial_date_lock")
    propose_correction
    token = Nokogiri::HTML(response.body).at_css("input[name='booking[correction_review_token]']")["value"]
    expect(response.body).to include("Reverse", "Schedule", "Confirm correction")
    expect(response.body).not_to include("The stay dates could not be updated.")

    propose_correction(correction_reason: "Wrong arrival date", correction_review_token: token)

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_sheet"')
    expect(flash[:notice]).to eq("Stay dates and charges updated.")
    expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(Date.current)
    expect(booking.booking_folio.folio_transactions.adjustment.count).to eq(1)
  end

  it "shows the proposed total alongside the correction instead of the original stay value" do
    prepare_posted_closed_night
    patch hotel_booking_action_edit_dates_path(hotel, booking), params: {
      booking: { check_in: Date.current, check_out: Date.current + 2.days }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("[data-booking-actions--stay-price-target='estimatedTotal']").text).to eq("199.98")
    expect(document.at_css("[data-booking-actions--stay-price-target='calculationStatus']").text).to eq("Proposed estimate")
    expect(booking.reload.total_amount).to eq("99.99".to_d)
  end

  it "retains submitted dates, reason, and review when accounting fails" do
    prepare_posted_closed_night
    grant_permission("manage_night_audit")
    grant_permission("override_financial_date_lock")
    propose_correction
    token = Nokogiri::HTML(response.body).at_css("input[name='booking[correction_review_token]']")["value"]
    allow(Financials::CreateJournalBatch).to receive(:call).and_raise("Journal refresh failed")

    propose_correction(correction_reason: "Wrong arrival date", correction_review_token: token)

    expect(response).to have_http_status(:unprocessable_content)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("textarea[name='booking[correction_reason]']").text.strip).to eq("Wrong arrival date")
    expect(document.at_css("input[name='booking[check_in]']")["value"]).to eq(Date.current.to_s)
    expect(response.body).to include("Journal refresh failed", "Confirm correction")
    expect(response.body).not_to include('action="complete_sheet"')
    expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(Date.yesterday)
    expect(booking.booking_folio.folio_transactions.adjustment).not_to exist
  end

  it "requires a reason on the server and retains the review" do
    prepare_posted_closed_night
    grant_permission("manage_night_audit")
    grant_permission("override_financial_date_lock")
    propose_correction
    token = Nokogiri::HTML(response.body).at_css("input[name='booking[correction_review_token]']")["value"]

    propose_correction(correction_reason: " ", correction_review_token: token)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Reason for correction is required.", "Confirm correction")
    expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(Date.yesterday)
  end

  it "reviews and confirms every selected group booking together" do
    prepare_posted_closed_night
    grant_permission("manage_night_audit")
    grant_permission("override_financial_date_lock")
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2,
      status: "checked_in", check_in: booking.check_in, check_out: booking.check_out)
    create(:booking_room, booking: sibling, room_type: room_type, rate_plan: rate_plan, room_number: "102", subtotal: room_type.base_price)
    create(:booking_folio, hotel: hotel, booking: sibling)
    Bookings::InventoryManager.new(sibling).deduct
    Bookings::PostClosedStayCharges.call(booking: sibling, previous_check_in: sibling.check_in, previous_check_out: sibling.check_out, user: user)
    group_params = { target_scope: "group", booking_ids: [ booking.id, sibling.id ] }
    patch hotel_booking_action_edit_dates_path(hotel, booking), params: group_params.merge(
      booking: { check_in: Date.current, check_out: Date.current + 1.day }
    ), headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }
    expect(response.body).to include(booking.reservation_reference, sibling.reservation_reference)
    token = Nokogiri::HTML(response.body).at_css("input[name='booking[correction_review_token]']")["value"]

    patch hotel_booking_action_edit_dates_path(hotel, booking), params: group_params.merge(
      booking: { check_in: Date.current, check_out: Date.current + 1.day,
        correction_reason: "Wrong group arrival date", correction_review_token: token }
    ), headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_sheet"')
    expect(flash[:notice]).to eq("2 bookings stay dates and charges updated.")
    expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(Date.current)
    expect(sibling.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(Date.current)
    expect(sibling.booking_folio.folio_transactions.adjustment.count).to eq(1)
  end

  def propose_correction(**correction)
    patch hotel_booking_action_edit_dates_path(hotel, booking), params: {
      booking: { check_in: Date.current, check_out: Date.current + 1.day }.merge(correction)
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }
  end

  def prepare_posted_closed_night
    prepare_closed_night
    result = Bookings::UpdateStayService.new(booking: booking, user: user,
      params: { check_in: Date.yesterday, check_out: Date.current }).call
    expect(result).to be_success
  end

  def prepare_closed_night
    booking.update_column(:status, "checked_in")
    create(:booking_folio, hotel: hotel, booking: booking)
    create(:hotel_business_date, hotel: hotel, business_date: Date.current - 1.day, status: "closed")
    audit = create(:night_audit, hotel: hotel, business_date: Date.current - 1.day, status: "completed")
    create(:night_audit_financial_summary, night_audit: audit, room_revenue: 0)
    Bookings::InventoryManager.new(booking).deduct
  end

  it "shows the proposed-dates banner without mutating on a dates proposal" do
    original = [ booking.check_in, booking.check_out ]

    get hotel_booking_action_edit_dates_path(hotel, booking), params: {
      proposal_kind: "dates",
      booking: { check_in: Date.current + 1.day, check_out: Date.current + 3.days }
    }, headers: { "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Check the proposed stay dates", "Nothing changes until you save")
    expect([ booking.reload.check_in, booking.check_out ]).to eq(original)
  end

  it "returns 422 with submitted values when a group batch selects no eligible booking" do
    group = create(:group_booking, hotel:)
    booking.update!(group_booking: group, group_position: 1)

    patch hotel_booking_action_edit_dates_path(hotel, booking), params: {
      target_scope: "group",
      booking_ids: [ "" ],
      booking: { check_in: Date.current + 3.days, check_out: Date.current + 4.days }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("The stay dates could not be updated", (Date.current + 3.days).iso8601)
    expect(booking.reload.check_in.to_date).to eq(Date.current)
  end

  it "updates dates for selected group bookings" do
    group = create(:group_booking, hotel:)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel:, group_booking: group, group_position: 2, status: "confirmed", check_in: booking.check_in, check_out: booking.check_out)
    create(:booking_room, booking: sibling, room_type:, rate_plan:, room_number: "102")

    patch hotel_booking_action_edit_dates_path(hotel, booking), params: {
      target_scope: "group",
      booking_ids: [ booking.id, sibling.id ],
      booking: { check_in: Date.current + 2.days, check_out: Date.current + 5.days }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(booking.reload.check_in.to_date).to eq(Date.current + 2.days)
    expect(sibling.reload.check_out.to_date).to eq(Date.current + 5.days)
    expect(booking.booking_rooms.first.reload.room_number).to eq("101")
    expect(sibling.booking_rooms.first.reload.room_number).to eq("102")
  end

  it "blocks ineligible, unauthorized, and cross-hotel access" do
    booking.update_column(:status, "completed")
    get hotel_booking_action_edit_dates_path(hotel, booking)
    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))

    role.role_permissions.destroy_all
    get hotel_booking_action_edit_dates_path(hotel, booking)
    expect(response).to redirect_to(root_path)

    grant_permission("manage_bookings")
    other_booking = create(:booking, hotel: other_hotel)
    get hotel_booking_action_edit_dates_path(hotel, other_booking)
    expect(response).to have_http_status(:not_found)
  end
end
