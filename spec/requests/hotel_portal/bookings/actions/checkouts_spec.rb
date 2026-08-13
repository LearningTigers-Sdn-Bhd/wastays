# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions checkouts", frozen_time: :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:other_hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Garden Suite", room_number_mode: "custom", room_numbers: %w[101 102]) }
  let(:booking) do
    create(:booking, hotel: hotel, guest_name: "Ada Lovelace", status: "checkout_required", check_in: Date.yesterday, check_out: Date.current).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: "101")
      create(:booking_folio, booking: record, hotel: hotel, status: "open")
    end
  end

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def create_group_child(group, position:, room_number:, guest_name:)
    create(:booking, hotel: hotel, group_booking: group, group_position: position, status: "checkout_required", guest_name: guest_name, check_in: Date.yesterday, check_out: Date.current).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: room_number)
      create(:booking_folio, booking: record, hotel: hotel, status: "open")
    end
  end

  def stub_checkout(success:, error: nil)
    allow(Bookings::WebhookTriggerService).to receive(:new).and_return(instance_double(Bookings::WebhookTriggerService, trigger: true))
    allow(Notifications::Dispatcher).to receive(:new).and_return(instance_double(Notifications::Dispatcher, call: true))
    allow(Checkouts::ProcessBookingCheckout).to receive(:call).and_return(OpenStruct.new(success?: success, error: error, booking: booking))
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    grant_permission(role, "manage_bookings")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET the checkout form" do
    it "renders the checkout Sheet with the settlement form in the primary frame" do
      get hotel_booking_action_checkout_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet dialog#booking-checkout-sheet[data-controller='panels-ui--sheet']")

      expect(dialog).to be_present
      expect(dialog["data-panels-ui-sheet-side"]).to eq("bottom")
      expect(dialog.text).to include("Checkout", "Finish guest bills")
      expect(dialog.text).not_to include("Folio List", "Settlement Details")
      expect(dialog.at_css("[data-controller~='booking-actions--checkout-settlement']")).to be_present
      expect(dialog.at_css("input[name='booking[checked_out_at]']")).to be_present
      expect(dialog.at_css(".panel-date-time-picker")).to be_present
      expect(dialog.text).to include("Folio reference", "Holder name", "Total balance", "Settlement", "Action", "Closes at checkout")
      expect(dialog.css("[data-booking-actions--checkout-settlement-target~='folioRow'] .panel-select-menu")).to be_empty
      expect(dialog.at_css("[data-booking-actions--checkout-settlement-target~='folioRow'] [data-booking-actions--checkout-settlement-target~='settlementButton']")).to be_present
      reference_link = dialog.at_css("[data-booking-actions--checkout-settlement-target~='folioRow'] a[target='_blank']")
      expect(reference_link).to be_present
      expect(reference_link["class"]).to include("underline")
      expect(dialog.at_css("[data-booking-actions--checkout-settlement-status-url-value]")).to be_present
      expect(dialog.css("[data-booking-actions--checkout-settlement-target='paymentFields']")).to be_empty
      expect(dialog.css("[data-testid='folio-resolver-list'] .panel-badge, [data-testid='folio-resolver-list'] .panel-alert")).to be_empty
      expect(dialog.css("[data-booking-actions--checkout-settlement-target~='folioRow'] .panel-collapsible")).to be_empty
      expect(dialog.at_css("button.panel-button[type='submit'][form='booking-checkout-form']")).to be_present
      expect(dialog.css("section.bg-card")).to be_empty
      resolver_list = dialog.at_css("[data-testid='folio-resolver-list']")
      expect(resolver_list["class"]).not_to include("divide-y", "border-y")
      expect(response.body).not_to include("<!DOCTYPE html>")
      expect(response.body).not_to include("offcanvas")
    end

    it "renders live deposit settlement rows for available deposits" do
      deposit = create(:deposit, booking: booking, hotel: hotel, amount: 125, status: "held")

      get hotel_booking_action_checkout_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-checkout-sheet")
      expect(dialog.text).to include("Deposits", "Original", "Applied", "Returned", "Available", "Apply", "Release")
      expect(dialog.text).to include("MYR 125.00")
      expect(dialog.at_css("tr[data-deposit-id='#{deposit.id}'][data-blocking='true']")).to be_present
      expect(dialog.at_css("a[data-turbo-frame='booking_action_sheet_secondary'][href*='/deposits/#{deposit.id}']")).to be_present
    end

    it "renders authorized credit override controls for Direct Bill above the limit" do
      grant_permission(role, "override_corporate_credit_limit")
      relationship = create(:hotel_corporate_account, :direct_bill, hotel: hotel, credit_limit: 50, credit_currency: "MYR")
      folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
      create(:folio_transaction, booking_folio: folio, amount: 100)

      get hotel_booking_action_checkout_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-checkout-sheet")
      prefix = "checkout_bookings[#{booking.id}][folios][#{folio.id}]"
      expect(dialog.text).to include("authorized override is required")
      expect(dialog.text).to include("Invoice to holder")
      expect(dialog.at_css("input[name='#{prefix}[credit_override]']")).to be_present
      expect(dialog.at_css("input[name='#{prefix}[credit_override_reason]']")).to be_present
    end

    it "renders the group target selector for a group booking" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")

      get hotel_booking_action_checkout_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("dialog#booking-checkout-sheet")
      expect(dialog.text).to include("Group checkout")
      expect(dialog.at_css("input[name='target_scope']")).to be_present
    end

    it "renders into the secondary frame when launched stacked" do
      get hotel_booking_action_checkout_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-checkout-sheet")).to be_present
    end

    it "reports current folio balances for polling" do
      folio = booking.booking_folios.first
      booking.update_columns(check_in: booking.check_out - 1.hour)
      folio.folio_forecasted_charges.destroy_all
      create(:folio_transaction, booking_folio: folio, amount: 75, transaction_type: "charge")

      get hotel_booking_action_checkout_folio_status_path(hotel, booking),
        params: { adjustments: { folio.id => "999.00" } },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.fetch("folios")).to include(
        hash_including("booking_id" => booking.id, "folio_id" => folio.id, "balance" => "75.0", "status" => "open")
      )
    end

    it "excludes future forecasts when an early checkout has no preview charges" do
      booking.update!(check_out: Date.current + 2.days)
      folio = booking.booking_folios.first
      create(:folio_forecasted_charge, booking_folio: folio, stay_date: Date.current + 1.day, amount: 75)
      allow(Folios::Charges::PostEarlyCheckoutCharges).to receive(:pending_preview).and_return([])

      get hotel_booking_action_checkout_folio_status_path(hotel, booking), headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:success)
      status = response.parsed_body.fetch("folios").find { |item| item.fetch("folio_id") == folio.id }
      expect(status.fetch("balance")).to eq("0.0")
    end

    it "returns live deposit amounts and blocks group deposits only for final group checkout" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")
      group_deposit = create(:deposit, :group_owned, group_booking: group, hotel: hotel, amount: 150, currency: booking.currency)

      get hotel_booking_action_checkout_folio_status_path(hotel, booking),
        params: { booking_ids: [ booking.id ] }, headers: { "Accept" => "application/json" }
      partial = response.parsed_body.fetch("deposits").find { |item| item.fetch("deposit_id") == group_deposit.id }
      expect(partial).to include("available_amount" => "150.0", "blocking" => false)

      get hotel_booking_action_checkout_folio_status_path(hotel, booking),
        params: { booking_ids: [ booking.id, sibling.id ] }, headers: { "Accept" => "application/json" }
      final = response.parsed_body.fetch("deposits").find { |item| item.fetch("deposit_id") == group_deposit.id }
      expect(final).to include("available_amount" => "150.0", "blocking" => true)
    end
  end

  describe "POST the checkout" do
    it "blocks checkout until a booking deposit has no available balance" do
      deposit = create(:deposit, booking: booking, hotel: hotel, amount: 100, status: "held")

      post hotel_booking_action_checkout_path(hotel, booking),
        params: { booking: { checked_out_at: Time.current.strftime("%Y-%m-%dT%H:%M") } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Resolve the remaining MYR 100.00 deposit balance before checkout")
      expect(booking.reload.status).to eq("checkout_required")
    end

    it "checks the booking out and completes the sheet on a Turbo submission" do
      stub_checkout(success: true)

      post hotel_booking_action_checkout_path(hotel, booking),
        params: { booking: { checked_out_at: Time.current.strftime("%Y-%m-%dT%H:%M") } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="booking_action_sheet"')
      expect(Checkouts::ProcessBookingCheckout).to have_received(:call).with(hash_including(booking: booking, hotel: hotel, user: user))
    end

    it "navigates to the control panel with the success flag on a direct request" do
      stub_checkout(success: true)

      post hotel_booking_action_checkout_path(hotel, booking),
        params: { booking: { checked_out_at: Time.current.strftime("%Y-%m-%dT%H:%M") } }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details", checkout_success: true))
      expect(flash[:notice]).to eq("Guest has been checked out.")
    end

    it "keeps the sheet open with the error when checkout fails" do
      stub_checkout(success: false, error: "Cannot check out with Guest Folio balance of MYR 50.00.")

      post hotel_booking_action_checkout_path(hotel, booking),
        params: { booking: { checked_out_at: Time.current.strftime("%Y-%m-%dT%H:%M") } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("dialog", "Cannot check out with Guest Folio balance of MYR 50.00.")
    end

    it "preserves submitted resolver, early-departure, and timestamp values after failure" do
      booking.update!(check_out: Date.current + 2.days)
      folio = booking.booking_folios.first
      create(:folio_transaction, booking_folio: folio, amount: 50, transaction_type: "charge")
      create(:deposit, booking: booking, hotel: hotel, amount: 125, status: "held")
      stub_checkout(success: false, error: "Folio settlement is still required.")

      post hotel_booking_action_checkout_path(hotel, booking),
        params: {
          booking: { checked_out_at: "" },
          checkout_bookings: {
            booking.id => {
              folios: {
                folio.id => {
                  action: "pay_now",
                  amount: "50.00",
                  payment_method: "bank_transfer",
                  payment_reference: ""
                }
              }
            }
          },
          early_departures: {
            booking.id => { apply_charge: "true", type: "percentage", value: "25", charge_amount: "12.50" }
          }
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:unprocessable_content)
      expect(document.at_css("input[name='booking[checked_out_at]']")["value"]).to eq("")
      expect(document.at_css("input[name='checkout_bookings[#{booking.id}][folios][#{folio.id}][action]']")["value"]).to eq("pay_now")
      expect(document.at_css("input[name='checkout_bookings[#{booking.id}][folios][#{folio.id}][amount]']")["value"]).to eq("50.00")
      expect(document.css("[name='checkout_bookings[#{booking.id}][folios][#{folio.id}][payment_method]']")).to be_empty
      expect(document.at_css("input[name='early_departures[#{booking.id}][apply_charge]'][value='true']")).to be_present
      expect(document.at_css("input[name='early_departures[#{booking.id}][value]']")["value"]).to eq("25")
      expect(document.text).to include("Deposits", "MYR 125.00")
    end

    it "blocks checkout-required submission without a timestamp" do
      post hotel_booking_action_checkout_path(hotel, booking),
        params: { booking: { checked_out_at: "" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML("Check-out date and time can't be blank."))
    end

    it "checks out the selected group bookings" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")
      stub_checkout(success: true)

      post hotel_booking_action_checkout_path(hotel, booking),
        params: { target_scope: "individual", booking_ids: [ booking.id, sibling.id ], booking: { checked_out_at: Time.current.strftime("%Y-%m-%dT%H:%M") } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:notice]).to eq("2 bookings checked out.")
    end

    it "blocks checkout without manage_bookings permission" do
      role.role_permissions.destroy_all

      post hotel_booking_action_checkout_path(hotel, booking),
        params: { booking: { checked_out_at: Time.current.strftime("%Y-%m-%dT%H:%M") } }

      expect(response).to have_http_status(:redirect)
      expect(booking.reload.status).to eq("checkout_required")
    end

    it "does not find a booking from another hotel" do
      other_booking = create(:booking, hotel: other_hotel, status: "checkout_required")

      post hotel_booking_action_checkout_path(hotel, other_booking),
        params: { booking: { checked_out_at: Time.current.strftime("%Y-%m-%dT%H:%M") } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the early-departure policy row" do
    let(:early_booking) do
      create(:booking, hotel: hotel, guest_name: "Grace Hopper", status: "checked_in", check_in: Date.current, check_out: Date.current + 2.days).tap do |record|
        create(:booking_room, booking: record, room_type: room_type, room_number: "102", subtotal: 400)
        create(:booking_folio, booking: record, hotel: hotel, status: "open")
      end
    end

    def activate_early_departure_policy(pricing_type: "fixed", rate_value: 90)
      ReservationPolicies::EnsureDefaults.call(hotel)
      hotel.hotel_reservation_policies.find_by!(policy_type: "early_departure")
        .update!(pricing_type: pricing_type, rate_value: rate_value)
    end

    it "offers follow-policy with the computed amount pre-filled and disabled" do
      activate_early_departure_policy

      get hotel_booking_action_checkout_path(hotel, early_booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("input[name='early_departures[#{early_booking.id}][charge_source]'][value='policy']")).to be_present
      amount_field = document.at_css("input[name='early_departures[#{early_booking.id}][policy_amount]']")
      expect(amount_field).to be_present
      expect(amount_field["disabled"]).to be_present
      expect(amount_field["value"]).to eq("MYR 90.00")
    end

    it "omits the policy option when the policy names no figure" do
      get hotel_booking_action_checkout_path(hotel, early_booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("input[type='radio'][name='early_departures[#{early_booking.id}][charge_source]']")).to be_nil
      expect(document.at_css("input[type='hidden'][name='early_departures[#{early_booking.id}][charge_source]'][value='custom']")).to be_present
    end

    # The submitted charge_amount is a hidden field the browser writes; on the
    # policy path the server recomputes it from the policy and ignores the input.
    it "charges the policy amount and ignores a tampered charge amount" do
      activate_early_departure_policy
      stub_checkout(success: true)

      post hotel_booking_action_checkout_path(hotel, early_booking),
        params: {
          booking: { checked_out_at: Time.current.strftime("%Y-%m-%dT%H:%M") },
          early_departures: {
            early_booking.id => { apply_charge: "true", charge_source: "policy", type: "amount", value: "5", charge_amount: "5.00" }
          }
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(Checkouts::ProcessBookingCheckout).to have_received(:call)
        .with(hash_including(early_departure_params: { apply_charge: "true", charge_amount: 90.to_d }))
    end

    it "keeps the staff-entered amount on the custom path" do
      activate_early_departure_policy
      stub_checkout(success: true)

      post hotel_booking_action_checkout_path(hotel, early_booking),
        params: {
          booking: { checked_out_at: Time.current.strftime("%Y-%m-%dT%H:%M") },
          early_departures: {
            early_booking.id => { apply_charge: "true", charge_source: "custom", type: "amount", value: "25", charge_amount: "25.00" }
          }
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(Checkouts::ProcessBookingCheckout).to have_received(:call)
        .with(hash_including(early_departure_params: { apply_charge: "true", charge_amount: 25.to_d }))
    end
  end
end
