# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions billing parties", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel:) }

  before do
    permission = Permission.find_by(slug: "manage_bookings") || create(:permission, slug: "manage_bookings", name: "Manage Bookings")
    create(:role_permission, role:, permission:)
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  it "opens a choice Sheet with guest and account workflows" do
    get hotel_booking_action_manage_billing_party_path(hotel, booking, mode: "choose"),
      headers: { "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("turbo-frame#booking_action_sheet dialog#billing-party-choice-sheet")).to be_present
    expect(document.text).to include("Add guest", "Add Corporate Account payer")
  end

  it "adds an account payer to the selected booking and completes the Sheet" do
    account = create(:hotel_corporate_account, hotel:)

    post hotel_booking_action_manage_billing_party_path(hotel, booking, mode: "add_account"), params: {
      billing_party: {
        apply_to: "booking:#{booking.id}", hotel_corporate_account_id: account.id,
        account_type: "company", settlement_type: "cash_bank"
      }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_sheet"', 'target="booking_action_sheet"')
    party = booking.booking_billing_parties.companies.sole
    expect(party).to have_attributes(hotel_corporate_account: account)
    expect(party.booking_folios.count).to eq(1)
  end

  it "shows an empty state when no corporate accounts are available" do
    get hotel_booking_action_manage_billing_party_path(hotel, booking, mode: "add_account"),
      headers: { "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    expect(document.text).to include("No active Corporate Accounts yet")
    expect(document.at_css("button[form='billing-party-form'][disabled]")).to be_present
  end

  it "offers every child room and an All option when adding a group account payer" do
    group = create(:group_booking, hotel:)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel:, group_booking: group, group_position: 2)
    create(:booking_room, booking:, room_number: "201")
    create(:booking_room, booking: sibling, room_number: "202")
    create(:hotel_corporate_account, hotel:)

    get hotel_booking_action_manage_billing_party_path(hotel, booking, mode: "add_account"),
      headers: { "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    option_nodes = Nokogiri::HTML(response.body).css("select[name='billing_party[apply_to]'] option")
    options = option_nodes
      .map { |option| [ option.text.squish, option["value"] ] }
    expect(options).to include(
      [ "Room 201", "booking:#{booking.id}" ],
      [ "Room 202", "booking:#{sibling.id}" ],
      [ "All rooms in group (2)", "group" ]
    )
    expect(option_nodes.find { |option| option["selected"] }["value"]).to eq("booking:#{booking.id}")
  end

  it "applies an account payer to every child in the group" do
    group = create(:group_booking, hotel:)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel:, group_booking: group, group_position: 2)
    account = create(:hotel_corporate_account, hotel:)

    attributes = {
      billing_party: { apply_to: "group", hotel_corporate_account_id: account.id, account_type: "company", settlement_type: "cash_bank" }
    }

    post hotel_booking_action_manage_billing_party_path(hotel, booking, mode: "add_account"), params: attributes
    expect(response.body).to include("Review group payer", "one external folio")
    expect(BookingBillingParty.companies.where(booking_id: [ booking.id, sibling.id ])).not_to exist

    post hotel_booking_action_manage_billing_party_path(hotel, booking, mode: "add_account"), params: attributes.merge(confirm_group: "1")
    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
    expect([ booking, sibling ].map { |child| child.booking_billing_parties.companies.count }).to eq([ 1, 1 ])
  end

  it "rejects a booking target outside the current group" do
    group = create(:group_booking, hotel:)
    booking.update!(group_booking: group, group_position: 1)
    foreign_target = create(:booking, hotel:)
    account = create(:hotel_corporate_account, hotel:)

    post hotel_booking_action_manage_billing_party_path(hotel, booking, mode: "add_account"), params: {
      billing_party: { apply_to: "booking:#{foreign_target.id}", hotel_corporate_account_id: account.id, settlement_type: "cash_bank" }
    }

    expect(response).to have_http_status(:not_found)
    expect(foreign_target.booking_billing_parties.companies).to be_empty
  end
end
