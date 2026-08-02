# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::NightAuditRuns", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:business_date) { Date.new(2026, 7, 29) }
  let(:hotel) { create(:hotel, :without_current_business_date, account:, plan:, status: "live", time_zone: "Kuala Lumpur") }
  let(:user) { create(:user, account:, role: "hotel_staff") }
  let(:role) { create(:role, account:, slug: "night_auditor", name: "Night Auditor") }
  let!(:manage_night_audit) { permission("manage_night_audit", "Manage Night Audit") }

  before do
    role.permissions << manage_night_audit
    create(:user_hotel_access, user:, hotel:, role:)
    create(:plan_feature, plan:, feature: create(:feature, feature_group:, slug: "no_show_auto_handling"), enabled: true)
    post login_path, params: { email: user.email, password: user.password }
    BusinessDates::ResetAuthority.call!(hotel:, date: business_date)
  end

  it "renders only the confirmation sheet on the first GET" do
    expect {
      get hotel_night_audit_run_path(hotel), headers: sheet_headers
    }.not_to change(NightAudit, :count)

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.at_css("turbo-frame#booking_action_sheet dialog#confirm-run-night-audit-sheet")).to be_present
    expect(response.body).to include("29 Jul 2026", "30 Jul 2026", "Continue", "Cancel")
    expect(response.body).not_to include("Payments &amp; charges", "Audit notes")
    expect(document.css("button").map { |button| button.text.squish }).not_to include("Run Night Audit")
  end

  it "captures the exact current page from the referrer when the sheet opens" do
    origin = hotel_stay_view_path(hotel)

    get hotel_night_audit_run_path(hotel),
      headers: sheet_headers.merge("Referer" => "http://www.example.com#{origin}")

    document = Nokogiri::HTML(response.body)
    expect(document.at_css("input[name='return_to']")["value"]).to eq(origin)
    expect(response.body).not_to include("start_date", "days=", "view=timeline")
  end

  it "explains the date timing instead of showing confirmation before Night Audit is available" do
    allow_any_instance_of(Hotel).to receive(:can_audit_date?).and_return(false)

    get hotel_night_audit_run_path(hotel), headers: sheet_headers

    document = Nokogiri::HTML(response.body)
    footer_labels = document.css("dialog#confirm-run-night-audit-sheet div.border-t button").map { |button| button.text.squish }
    expect(response.body).to include(
      "Night Audit is not available yet",
      "Current business date: 29 Jul 2026",
      "29 Jul 2026 remains open",
      "move the hotel to 30 Jul 2026 after 02:00 AM hotel time"
    )
    expect(footer_labels).to eq([ "Close" ])
    expect(response.body).not_to include(">Continue<", ">Cancel<")
  end

  it "continues into Confirm when fresh checks are clear" do
    post start_review_hotel_night_audit_run_path(hotel),
      params: { return_to: hotel_front_desk_path(hotel) },
      headers: sheet_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bookings", "Payments &amp; charges", "Confirm")
    expect(response.body).to include("Ready to run", "Run Night Audit")
    expect(response.body).to include('data-active-step="3"')
    document = Nokogiri::HTML(response.body)
    footer = document.at_css("dialog#run-night-audit-sheet footer")
    expect(footer.text.squish).to include("Close", "Run Night Audit")
    expect(footer.at_css("button[form='night-audit-confirm-form']")).to be_present
    expect(response.body).not_to include("More Actions", ">Refresh<", "Close date anyway")
  end

  it "runs detection on Continue and opens Bookings for live detected statuses" do
    due_out = create_booking(status: "checked_in", check_in: business_date - 1.day, check_out: business_date, checked_in_at: hotel_time(14), token: "WS-DUE-1")
    arrival = create_booking(status: "confirmed", check_in: business_date, check_out: business_date + 1.day, token: "WS-ARR-1")
    create(:booking_folio, hotel:, booking: due_out)
    create(:booking_folio, hotel:, booking: arrival)

    post start_review_hotel_night_audit_run_path(hotel), headers: sheet_headers

    expect(response).to have_http_status(:ok)
    expect(due_out.reload.status).to eq("due_out_detected")
    expect(arrival.reload.status).to eq("no_show_detected")
    expect(response.body).to include('data-active-step="1"', "Bookings")
    expect(response.body).not_to include("due_out_detected", "no_show_detected")
  end

  it "opens Payments & charges when only a financial item needs attention" do
    booking = create_booking(status: "checked_in", check_in: business_date - 1.day, check_out: business_date + 1.day, checked_in_at: hotel_time(14), token: "WS-FOLIO-1")

    post start_review_hotel_night_audit_run_path(hotel), headers: sheet_headers

    expect(response).to have_http_status(:ok)
    expect(booking.reload.status).to eq("checked_in")
    expect(response.body).to include('data-active-step="2"', "Payments &amp; charges", "Create folio")
    expect(Nokogiri::HTML(response.body).text).not_to include("missing_folio")
  end

  it "shows a direct manager close action only while items need attention" do
    role.permissions << permission("override_financial_date_lock", "Override Financial Date Lock")
    create_booking(status: "checked_in", check_in: business_date - 1.day, check_out: business_date + 1.day, checked_in_at: hotel_time(14), token: "WS-MANAGER-1")
    manual_review!

    get hotel_night_audit_run_path(hotel), headers: sheet_headers

    footer = Nokogiri::HTML(response.body).at_css("dialog#run-night-audit-sheet footer")
    expect(footer.text.squish).to include("Close", "Close date anyway…")
    expect(footer.text).not_to include("Run Night Audit", "Refresh", "More Actions")
    expect(footer.at_css("a[data-turbo-frame='booking_action_sheet_secondary']")).to be_present
  end

  it "resumes a post-close financial recovery at Payments & charges without confirmation" do
    create_booking(status: "checked_in", check_in: business_date - 1.day, check_out: business_date + 1.day, checked_in_at: hotel_time(14), token: "WS-RECOVER-1")
    create(:night_audit,
      hotel:, business_date:, status: "blocked", trigger_mode: "manual", performed_by_user: user,
      blocked_details: { "missing_nightly_charges" => [ { "booking_id" => 123 } ] })

    get hotel_night_audit_run_path(hotel), headers: sheet_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('dialog id="run-night-audit-sheet"', 'data-active-step="2"')
    expect(response.body).not_to include("confirm-run-night-audit-sheet")
  end

  it "routes booking actions from each booking's live status into the secondary sheet" do
    role.permissions << permission("manage_bookings", "Manage Bookings")
    no_show = create_booking(status: "no_show_detected", check_in: business_date, check_out: business_date + 1.day, token: "WS-NOSHOW-1", no_show_detected_business_date: business_date)
    due_out = create_booking(status: "due_out_detected", check_in: business_date - 1.day, check_out: business_date, checked_in_at: hotel_time(14), token: "WS-DUE-2")
    checkout = create_booking(status: "checkout_required", check_in: business_date - 1.day, check_out: business_date, checked_in_at: hotel_time(14), token: "WS-CHECKOUT-1")
    [ no_show, due_out, checkout ].each { |booking| create(:booking_folio, hotel:, booking:) }
    manual_review!

    get hotel_night_audit_run_path(hotel), headers: sheet_headers

    links = Nokogiri::HTML(response.body).css("a[data-turbo-frame='booking_action_sheet_secondary']")
    hrefs = links.to_h { |link| [ link.text.squish, URI.parse(link["href"]) ] }
    expect(hrefs.fetch("Record an earlier check-in").path).to eq(hotel_booking_action_review_backdated_check_in_path(hotel, no_show))
    expect(hrefs.fetch("Mark as no-show").path).to eq(hotel_booking_action_mark_no_show_path(hotel, no_show))
    expect(hrefs.fetch("Handle late checkout").path).to eq(hotel_booking_action_late_checkout_path(hotel, due_out))
    expect(hrefs.fetch("Complete checkout").path).to eq(hotel_booking_action_checkout_path(hotel, checkout))
    expect(hrefs.values).to all(satisfy { |uri| Rack::Utils.parse_nested_query(uri.query).key?("return_to") })
    expect(response.body).to include("Choose an action")
    expect(response.body).not_to include("Check in</a>", "Review due out", "Extend stay")
  end

  it "rechecks state before scheduling and returns to Payments & charges when it changed" do
    manual_review!
    allow(NightAudits::Schedule).to receive(:call).and_wrap_original do |original, **arguments|
      create_booking(status: "checked_in", check_in: business_date - 1.day, check_out: business_date + 1.day, checked_in_at: hotel_time(14), token: "WS-LATE-1")
      original.call(**arguments)
    end

    expect {
      post hotel_night_audit_run_path(hotel),
        params: { night_audit_run: { notes: "Ready at review time" } },
        headers: sheet_headers
    }.not_to have_enqueued_job(NightAudits::RunJob)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('data-active-step="2"', "needs attention")
  end

  it "renders a focused timestamp correction in the secondary sheet" do
    role.permissions << permission("manage_bookings", "Manage Bookings")
    booking = create_booking(status: "checked_in", check_in: business_date - 1.day, check_out: business_date + 1.day, token: "WS-TIME-1")
    manual_review!

    get booking_timestamp_hotel_night_audit_run_path(hotel),
      params: { booking_id: booking.id, timestamp_kind: "check_in", return_to: hotel_night_audit_run_path(hotel) },
      headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.at_css("turbo-frame#booking_action_sheet_secondary dialog#add-booking-time-sheet")).to be_present
    expect(response.body).to include("Add check-in time", "Correction reason")
  end

  it "returns status safely and preserves completion toasts" do
    audit = create(:night_audit, hotel:, business_date:, status: "completed")

    get status_hotel_night_audit_run_path(hotel), params: { audit_id: audit.id, return_to: "https://evil.example/steal" }

    expect(response.parsed_body).to include(
      "state" => "completed",
      "refresh_url" => hotel_front_desk_path(hotel),
      "report_url" => hotel_reports_night_audit_path(hotel, audit)
    )
    expect(flash[:toast]).to include(
      message: "Night audit completed",
      action: { label: "View details", url: hotel_reports_night_audit_path(hotel, audit) }
    )
  end

  it "uses the force-close completion toast contract" do
    audit = create(:night_audit, hotel:, business_date:, status: "completed", force_closed: true)

    get status_hotel_night_audit_run_path(hotel), params: { audit_id: audit.id, return_to: hotel_front_desk_path(hotel) }

    expect(flash[:toast]).to include(
      message: "Business date force-closed",
      description: "Business date advanced from 29 Jul 2026 to 30 Jul 2026."
    )
  end

  it "rejects access without Manage Night Audit" do
    role.permissions.delete(manage_night_audit)

    get hotel_night_audit_run_path(hotel), headers: sheet_headers

    expect(response).to redirect_to(root_path)
  end

  private

  def permission(slug, name)
    Permission.find_or_create_by!(slug:) { |record| record.name = name }
  end

  def sheet_headers
    { "Turbo-Frame" => "booking_action_sheet" }
  end

  def hotel_time(hour)
    hotel.hotel_time_zone.local(2026, 7, 28, hour)
  end

  def create_booking(status:, check_in:, check_out:, token:, **attributes)
    create(:booking, hotel:, status:, check_in:, check_out:, confirmation_token: token, **attributes)
  end

  def manual_review!
    create(:night_audit,
      hotel:, business_date:, status: "preparing", trigger_mode: "manual", performed_by_user: user,
      started_at: nil, completed_at: nil)
  end
end
