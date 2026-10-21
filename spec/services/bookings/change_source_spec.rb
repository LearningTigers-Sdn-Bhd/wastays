# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ChangeSource do
  let(:actor) { create(:user, name: "Front Desk") }

  it "changes the source and records who changed it from what" do
    booking = create(:booking, source: "phone")

    result = described_class.call(booking:, actor:, source: "booking_com")

    expect(result).to be_success
    expect(booking.reload.source).to eq("booking_com")
    expect(booking).to be_ota_booking
    log = BookingAuditLog.find_by!(auditable: booking, action_type: "source_changed")
    expect(log).to have_attributes(user: actor, category: "stay", old_value: { "source" => "phone" }, new_value: { "source" => "booking_com" })
  end

  it "accepts a source spelled the way a channel writes it" do
    booking = create(:booking, source: "phone")

    expect(described_class.call(booking:, actor:, source: "Booking.com ")).to be_success
    expect(booking.reload.source).to eq("booking_com")
  end

  it "refuses a system source" do
    booking = create(:booking, source: "phone")

    result = described_class.call(booking:, actor:, source: "channex")

    expect(result).not_to be_success
    expect(result.errors).to contain_exactly("Channex is not an available booking source.")
    expect(booking.reload.source).to eq("phone")
  end

  it "refuses an inactive source" do
    create(:booking_source, key: "old_agency", label: "Old Agency", kind: "manual", active: false)
    booking = create(:booking, source: "phone")

    expect(described_class.call(booking:, actor:, source: "old_agency")).not_to be_success
    expect(booking.reload.source).to eq("phone")
  end

  it "refuses a blank or unchanged source" do
    booking = create(:booking, source: "phone")

    expect(described_class.call(booking:, actor:, source: "").errors).to contain_exactly("Choose a booking source.")
    expect(described_class.call(booking:, actor:, source: "phone").errors).to contain_exactly("The booking is already recorded as Phone.")
    expect(BookingAuditLog.where(auditable: booking, action_type: "source_changed")).not_to exist
  end

  describe "a travel agent source" do
    let(:hotel) { create(:hotel) }
    let(:agent) { create(:hotel_corporate_account, hotel:, account_type: "travel_agent") }
    let(:booking) { create(:booking, hotel:, source: "phone") }

    def room_route_target(booking)
      room_code = TransactionCodes::Resolver.for(hotel).room_revenue
      booking.folio_routing_rules.active.find_by(transaction_code: room_code)&.target_folio
    end

    it "puts the booking under the agent and bills its room charges to them" do
      result = described_class.call(booking:, actor:, source: "travel_agent", travel_agent_account_id: agent.id)

      expect(result.errors).to be_empty
      expect(booking.reload).to have_attributes(source: "travel_agent", hotel_corporate_account_id: agent.id)
      expect(room_route_target(booking).hotel_corporate_account_id).to eq(agent.id)
      log = BookingAuditLog.find_by!(auditable: booking, action_type: "source_changed")
      expect(log.new_value).to eq("source" => "travel_agent", "travel_agent" => agent.corporate_account.name)
    end

    it "bills the package extras to the agent too" do
      jetty_fee = create(:hotel_extra_charge, hotel:, bill_to_travel_agent: true)
      cake = create(:hotel_extra_charge, hotel:)

      described_class.call(booking:, actor:, source: "travel_agent", travel_agent_account_id: agent.id)

      routed = booking.folio_routing_rules.active.to_h { |rule| [ rule.transaction_code_id, rule.target_folio.hotel_corporate_account_id ] }
      expect(routed).to include(jetty_fee.transaction_code_id => agent.id)
      expect(routed).not_to have_key(cake.transaction_code_id)
    end

    it "leaves a posted package extra for the Billing tab" do
      jetty_fee = create(:hotel_extra_charge, hotel:, bill_to_travel_agent: true)
      folio = create(:booking_folio, booking:, hotel:)
      create(:folio_transaction, booking_folio: folio, transaction_code: jetty_fee.transaction_code)

      result = described_class.call(booking:, actor:, source: "travel_agent", travel_agent_account_id: agent.id)

      expect(result.errors).to contain_exactly("Charges the agent pays for have already been posted. Move them to the agent from the Billing tab.")
    end

    it "requires an active travel agent of this hotel" do
      company = create(:hotel_corporate_account, hotel:)

      [ nil, company.id, create(:hotel_corporate_account, account_type: "travel_agent").id ].each do |account_id|
        result = described_class.call(booking:, actor:, source: "travel_agent", travel_agent_account_id: account_id)
        expect(result.errors).to contain_exactly("Choose the travel agent this booking is under.")
      end
      expect(booking.reload.source).to eq("phone")
    end

    it "moves a travel agent booking to another agent" do
      other = create(:hotel_corporate_account, hotel:, account_type: "travel_agent")
      described_class.call(booking:, actor:, source: "travel_agent", travel_agent_account_id: agent.id)

      result = described_class.call(booking: booking.reload, actor:, source: "travel_agent", travel_agent_account_id: other.id)

      expect(result.errors).to be_empty
      expect(booking.reload.hotel_corporate_account_id).to eq(other.id)
      expect(room_route_target(booking).hotel_corporate_account_id).to eq(other.id)
    end

    it "says so when the booking is already under that agent" do
      described_class.call(booking:, actor:, source: "travel_agent", travel_agent_account_id: agent.id)

      result = described_class.call(booking: booking.reload, actor:, source: "travel_agent", travel_agent_account_id: agent.id)

      expect(result.errors).to contain_exactly("The booking is already under #{agent.corporate_account.name}.")
    end

    it "leaves posted room charges for the Billing tab" do
      folio = create(:booking_folio, booking:, hotel:)
      create(:folio_transaction, booking_folio: folio, transaction_code: TransactionCodes::Resolver.for(hotel).room_revenue)

      result = described_class.call(booking:, actor:, source: "travel_agent", travel_agent_account_id: agent.id)

      expect(result.errors).to contain_exactly("Charges the agent pays for have already been posted. Move them to the agent from the Billing tab.")
      expect(booking.reload).to have_attributes(source: "phone", hotel_corporate_account_id: nil)
    end

    it "keeps the agent's billing when the source moves off Travel Agent" do
      described_class.call(booking:, actor:, source: "travel_agent", travel_agent_account_id: agent.id)

      expect(described_class.call(booking: booking.reload, actor:, source: "email")).to be_success
      expect(booking.reload).to have_attributes(source: "email", hotel_corporate_account_id: agent.id)
    end
  end

  describe "a group" do
    let(:hotel) { create(:hotel) }
    let(:group) { create(:group_booking, hotel:) }
    let!(:first) { create(:booking, hotel:, group_booking: group, group_position: 1, source: "phone") }
    let!(:second) { create(:booking, hotel:, group_booking: group, group_position: 2, source: "phone") }
    let(:agent) { create(:hotel_corporate_account, hotel:, account_type: "travel_agent") }

    it "puts every room under the agent from any one room" do
      result = described_class.call(booking: second, actor:, source: "travel_agent", travel_agent_account_id: agent.id, apply_to_group: "1")

      expect(result.errors).to be_empty
      expect([ first, second ].map { |booking| booking.reload.hotel_corporate_account_id }).to eq([ agent.id, agent.id ])
      expect(BookingAuditLog.where(action_type: "source_changed").count).to eq(2)
    end

    it "changes only the one room when asked" do
      described_class.call(booking: second, actor:, source: "email", apply_to_group: "0")

      expect([ first.reload.source, second.reload.source ]).to eq(%w[phone email])
    end

    it "changes nothing when one room is locked, and names it" do
      first.update!(channel_manager_reference: "CHX-9")

      result = described_class.call(booking: second, actor:, source: "email", apply_to_group: "1")

      expect(result.errors.sole).to end_with(": This booking came from the channel manager, which owns its source.")
      expect([ first.reload.source, second.reload.source ]).to eq(%w[phone phone])
    end
  end

  describe "locked bookings" do
    it "refuses a channel manager booking" do
      booking = create(:booking, source: "agoda", channel_manager_reference: "CHX-1")

      result = described_class.call(booking:, actor:, source: "phone")

      expect(result.errors).to contain_exactly("This booking came from the channel manager, which owns its source.")
      expect(booking.reload.source).to eq("agoda")
    end

    it "refuses a booking with channel settlements" do
      allocation = create(:channel_settlement_allocation)
      booking = allocation.booking

      result = described_class.call(booking:, actor:, source: "phone")

      expect(result.errors).to contain_exactly("This booking has channel settlements recorded against its source.")
    end

    it "refuses a booking with an OTA billing party" do
      booking = create(:booking, source: "agoda")
      create(:booking_billing_party, booking:, party_kind: "ota", hotel_corporate_account: nil,
        booking_source: BookingSource.find_by!(key: "agoda"))

      result = described_class.call(booking:, actor:, source: "phone")

      expect(result.errors).to contain_exactly("This booking has an OTA billing party for its current source.")
    end

    it "refuses a booking with an issued e-invoice but not a cancelled one" do
      booking = create(:booking, source: "phone")
      submission = create(:e_invoice_submission, booking:, hotel: booking.hotel, status: "valid")

      expect(described_class.call(booking:, actor:, source: "email").errors)
        .to contain_exactly("An e-invoice has already been issued for this booking.")

      submission.update!(status: "cancelled")
      expect(described_class.call(booking:, actor:, source: "email")).to be_success
    end
  end
end
