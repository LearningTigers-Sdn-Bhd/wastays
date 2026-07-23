# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions checkouts", :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
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
      expect(dialog.text).to include("Checkout", "Resolve folios")
      expect(dialog.text).not_to include("Folio List", "Settlement Details")
      expect(dialog.at_css("[data-controller~='booking-actions--checkout-settlement']")).to be_present
      expect(dialog.at_css("input[name='booking[checked_out_at]']")).to be_present
      expect(dialog.at_css(".panel-date-time-picker")).to be_present
      expect(dialog.at_css("[data-booking-actions--checkout-settlement-target~='folioRow'] .panel-select-menu")).to be_present
      # Settlement controls render inline on the folio row (no expand step)
      expect(dialog.at_css("[data-booking-actions--checkout-settlement-target~='folioRow'] [data-booking-actions--checkout-settlement-target='paymentFields']")).to be_present
      expect(dialog.css("[data-booking-actions--checkout-settlement-target~='folioRow'] .panel-collapsible")).to be_empty
      expect(dialog.at_css("button.panel-button[type='submit'][form='booking-checkout-form']")).to be_present
      expect(dialog.css("section.bg-card")).to be_empty
      resolver_list = dialog.at_css("[data-testid='folio-resolver-list']")
      expect(resolver_list["class"]).not_to include("divide-y", "border-y")
      expect(response.body).not_to include("<!DOCTYPE html>")
      expect(response.body).not_to include("offcanvas")
    end

    it "renders held-deposit controls through PanelsUI with top-level parameter names" do
      folio = booking.booking_folios.first
      create(:deposit, booking: booking, hotel: hotel, booking_folio: folio, amount: 125, status: "held")

      get hotel_booking_action_checkout_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-checkout-sheet")
      expect(dialog.at_css("input.panel-switch__input[name='release_security_deposit'][role='switch']")).to be_present
      expect(dialog.at_css("select[name='security_deposit_release_method']")).to be_present
      expect(dialog.at_css("input[name='security_deposit_release_reference']")).to be_present
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
  end

  describe "POST the checkout" do
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

      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "booking_details", checkout_success: true))
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

    it "preserves submitted resolver, early-departure, timestamp, and deposit values after failure" do
      booking.update!(check_out: Date.current + 2.days)
      folio = booking.booking_folios.first
      create(:folio_transaction, booking_folio: folio, amount: 50, transaction_type: "charge")
      create(:deposit, booking: booking, hotel: hotel, booking_folio: folio, amount: 125, status: "held")
      stub_checkout(success: false, error: "Payment reference is required.")

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
          },
          release_security_deposit: "1",
          security_deposit_release_method: "bank_transfer",
          security_deposit_release_reference: "DEP-42"
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:unprocessable_content)
      expect(document.at_css("input[name='booking[checked_out_at]']")["value"]).to eq("")
      expect(document.at_css("select[name='checkout_bookings[#{booking.id}][folios][#{folio.id}][payment_method]'] option[selected]")["value"]).to eq("bank_transfer")
      expect(document.at_css("input[name='checkout_bookings[#{booking.id}][folios][#{folio.id}][payment_reference]']")["value"]).to eq("")
      expect(document.at_css("input[name='early_departures[#{booking.id}][apply_charge]'][value='true']")).to be_present
      expect(document.at_css("input[name='early_departures[#{booking.id}][value]']")["value"]).to eq("25")
      expect(document.at_css("select[name='security_deposit_release_method'] option[selected]")["value"]).to eq("bank_transfer")
      expect(document.at_css("input[name='security_deposit_release_reference']")["value"]).to eq("DEP-42")
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
end
