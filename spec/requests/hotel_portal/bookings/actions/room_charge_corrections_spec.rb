# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions room charge corrections", frozen_time: :business_day, type: :request do
  include_context "completed room-charge correction"

  before { sign_in_as(actor) }

  it "shows the correction action instead of room and rate changes after checkout" do
    get hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")
    expect(response).to have_http_status(:success)
    panel = Nokogiri::HTML(response.body).at_css("#room-rate-panel")
    expect(panel.text).to include("Correct room charges")
    expect(panel.text).not_to include("Change rate", "Change room")
  end

  it "preserves active-booking room and rate actions" do
    booking.update_column(:status, "checked_in")
    get hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")
    panel = Nokogiri::HTML(response.body).at_css("#room-rate-panel")
    expect(panel.text).to include("Change rate", "Change room")
    expect(panel.text).not_to include("Correct room charges")
  end

  it "renders a per-night sheet with a reason input" do
    get hotel_booking_action_correct_room_charges_path(hotel, booking), headers: { "Turbo-Frame" => "booking_action_sheet" }
    expect(response).to have_http_status(:success)
    dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-room-charge-correction-sheet")
    expect(dialog.text).to include("Set all nights", "Correction reason", "Includes applicable room taxes. Tourism Tax is handled separately.", "Closed folios reopen")
    expect(dialog.css("input[name='room_charge_correction[nightly_amounts][#{correction_date.iso8601}]']").first["value"]).to eq("108.00")
    expect(dialog.css("textarea").length).to eq(1)
    expect(dialog.css("select")).to be_empty
    expect(dialog.text).not_to include("Correction note")
  end

  it "reviews and confirms through the requesting Turbo sheet" do
    post hotel_booking_action_review_room_charge_correction_path(hotel, booking), params: { room_charge_correction: correction_input }, headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Review room-charge correction", "108.00", "86.40", "-21.60", "Confirm correction", "Cancel")
    token = Nokogiri::HTML(response.body).at_css("input[name='room_charge_correction[correction_review_token]']")["value"]
    post hotel_booking_action_confirm_room_charge_correction_path(hotel, booking), params: {
      return_to: hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate"),
      room_charge_correction: correction_input.merge(correction_review_token: token)
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }
    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_sheet"', 'target="booking_action_sheet_secondary"')
    expect(booking.reload.total_amount).to eq("86.4".to_d)
  end

  it "retains the explanation and amount when returning from review" do
    post hotel_booking_action_review_room_charge_correction_path(hotel, booking), params: { back: "1", room_charge_correction: correction_input }
    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("textarea").text.strip).to eq(correction_input[:correction_reason])
    expect(document.at_css("input[name='room_charge_correction[nightly_amounts][#{correction_date.iso8601}]']")["value"]).to eq("86.40")
    expect(response.body).not_to include("Confirm correction")
  end

  it "retains submitted values with validation errors" do
    post hotel_booking_action_review_room_charge_correction_path(hotel, booking), params: { room_charge_correction: correction_input.merge(nightly_amounts: amounts_for("-1")) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("nonnegative", correction_input[:correction_reason])
    expect(booking.reload.total_amount).to eq(108)
  end

  it "validates missing required values instead of raising a controller error" do
    post hotel_booking_action_review_room_charge_correction_path(hotel, booking)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("A correction reason is required.")
  end

  it "ignores submitted dates, room changes and status changes" do
    before_values = booking.attributes.slice("check_in", "check_out", "status")
    values = correction_input.merge(status: "checked_in", check_out: (Date.current + 10.days).to_s, room_number: "999")
    post hotel_booking_action_review_room_charge_correction_path(hotel, booking), params: { room_charge_correction: values }
    expect(response).to have_http_status(:success)
    expect(booking.reload.attributes.slice(*before_values.keys)).to eq(before_values)
    expect(room.reload.room_number).to eq("101")
  end

  it "rejects cross-hotel access" do
    other = create(:booking, status: "completed")
    get hotel_booking_action_correct_room_charges_path(hotel, other)
    expect(response).to have_http_status(:not_found)
  end

  it "disables and rejects the action without correction permissions" do
    role.role_permissions.where(permission: Permission.find_by!(slug: "override_booking_rate")).delete_all
    get hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")
    panel = Nokogiri::HTML(response.body).at_css("#room-rate-panel")
    expect(panel.text).to include("Correct room charges", "Needs the \"override booking rate\" permission.")
    expect(panel.at_css("a[href*='correct-room-charges']")).to be_nil
    get hotel_booking_action_correct_room_charges_path(hotel, booking)
    expect(response).to redirect_to(root_path)
  end
end
