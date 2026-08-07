require 'rails_helper'

RSpec.describe ChannelManagers::ChannexAdapter do
  let(:hotel) { create(:hotel, name: "Test Hotel", city: "KL") }
  let!(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe", quantity: 5, max_adults: 2) }
  let(:adapter) { described_class.new(hotel: hotel) }
  let(:client_double) { instance_double(Channex::Client) }

  before do
    allow(Channex::Client).to receive(:new).and_return(client_double)
  end

  describe '#onboard_hotel' do
    it 'creates property, room types and rate plans' do
      # Mock Property Creation
      expect(client_double).to receive(:post).with("/properties", hash_including(property: hash_including(title: "Test Hotel", timezone: "Asia/Kuala_Lumpur")))
        .and_return({ "data" => { "id" => "ch_prop_123" } })

      # Mock Room Type Creation
      expect(client_double).to receive(:post).with("/room_types", hash_including(room_type: hash_including(title: "Deluxe", property_id: "ch_prop_123")))
        .and_return({ "data" => { "id" => "ch_rt_123" } })

      # Mock Rate Plan Creation
      expect(client_double).to receive(:post).with("/rate_plans", hash_including(rate_plan: hash_including(title: "Standard Rate (Deluxe)", room_type_id: "ch_rt_123")))
        .and_return({ "data" => { "id" => "ch_rp_123" } })

      result = adapter.onboard_hotel

      expect(result.success?).to be true
      expect(hotel.channel_mapping.external_id).to eq("ch_prop_123")
      expect(room_type.channel_mapping.external_id).to eq("ch_rt_123")
      expect(room_type.room_type_rate_plans.first.channel_mapping.external_id).to eq("ch_rp_123")
      end
      end

  describe 'per-person properties' do
    let(:hotel) { create(:hotel, :per_person, name: "Test Hotel", city: "KL") }

    it 'onboards successfully, skipping the rate plans Channex cannot represent' do
      expect(client_double).to receive(:post).with("/properties", anything)
        .and_return({ "data" => { "id" => "ch_prop_123" } })
      expect(client_double).to receive(:post).with("/room_types", anything)
        .and_return({ "data" => { "id" => "ch_rt_123" } })
      expect(client_double).not_to receive(:post).with("/rate_plans", anything)

      result = adapter.onboard_hotel

      expect(result.success?).to be true
      expect(hotel.reload.channel_mapping.external_id).to eq("ch_prop_123")
    end

    it 'reports that nothing was pushed rather than a successful ARI sync' do
      hotel.create_channel_mapping(provider: "channex", external_id: "ch_prop_123")
      create(:rate_plan, hotel: hotel, room_type: room_type)

      result = adapter.push_ari(date_range: Date.current..(Date.current + 2.days), sync_availability: false)

      expect(result.success?).to be true
      expect(result.message).to match(/sells per guest/i)
    end
  end

  describe '#sync_rate_plan' do
    let!(:hotel_mapping) { create(:channel_mapping, mappable: hotel, external_id: "ch_prop_123") }
    let!(:room_type_mapping) { create(:channel_mapping, mappable: room_type, external_id: "ch_rt_123") }

    it 'does not call Channex and returns nil for a per_person rate plan' do
      hotel.update!(sell_mode: "per_person")
      rate_plan = create(:rate_plan, hotel: hotel, room_type: room_type)

      expect(client_double).not_to receive(:post)
      expect(client_double).not_to receive(:put)
      expect(adapter.sync_rate_plan(rate_plan)).to be_nil
    end

    it 'still syncs a per_room rate plan (regression guard)' do
      rate_plan = create(:rate_plan, hotel: hotel, room_type: room_type)
      create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan)

      allow(client_double).to receive(:post).and_return({ "data" => { "id" => "ch_rp_999" } })

      result = adapter.sync_rate_plan(rate_plan)

      expect(result).not_to be_nil
      expect(client_double).to have_received(:post).with("/rate_plans", hash_including(rate_plan: hash_including(sell_mode: "per_room")))
    end
  end

  describe '#push_ari' do
    let(:start_date) { Date.current }
    let(:end_date) { start_date + 2.days }
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, room_type: room_type, name: "Standard Rate") }

    before do
      # Setup mappings
      hotel.create_channel_mapping(provider: "channex", external_id: "ch_prop_123")
      room_type.create_channel_mapping(provider: "channex", external_id: "ch_rt_123")
      room_type.room_type_rate_plans.find_by!(rate_plan: rate_plan).create_channel_mapping(provider: "channex", external_id: "ch_rp_123")
      allow(client_double).to receive(:get).with("/channels").and_return({ "data" => [] })

      # push_restrictions_values looks up connected channels to apply per-channel
      # derived pricing overrides; stub an empty channel list for these specs.
      allow(client_double).to receive(:get).with("/channels").and_return({ "data" => [] })

      # Create ARI data - ensure contiguous dates with SAME values for grouping
      (start_date..end_date).each do |date|
        room_type.room_inventories.create!(date: date, quantity: 10, status: "open")
        rate_plan.room_rates.create!(date: date, price: 200.0, currency: "MYR", room_type: room_type)
      end
    end

    it 'optimizes the payload using date ranges (date_from and date_to)' do
      # Expect availability to be grouped into ONE range
      expect(client_double).to receive(:post).with("/availability", {
        values: [
          {
            property_id: "ch_prop_123",
            room_type_id: "ch_rt_123",
            date_from: start_date.to_s,
            date_to: end_date.to_s,
            availability: 10
          }
        ]
      }).and_return({ "data" => { "id" => "task_1" } })

      # Expect restrictions/rates to be grouped into ONE range with defaults for restrictions
      expect(client_double).to receive(:post).with("/restrictions", {
        values: [
          {
            property_id: "ch_prop_123",
            rate_plan_id: "ch_rp_123",
            date_from: start_date.to_s,
            date_to: end_date.to_s,
            rate: "200.00",
            min_stay_arrival: 1,
            max_stay_arrival: 999,
            closed_to_arrival: 0,
            closed_to_departure: 0,
            stop_sell: 0
          }
        ]
      }).and_return({ "data" => { "id" => "task_2" } })

      result = adapter.push_ari(date_range: (start_date..end_date))
      expect(result.success?).to be true
    end

    it 'creates multiple ranges for non-contiguous dates or different values' do
      # Add a fourth day with a DIFFERENT price
      diff_date = start_date + 3.days
      rate_plan.room_rates.create!(date: diff_date, price: 300.0, currency: "MYR", room_type: room_type)
      room_type.room_inventories.create!(date: diff_date, quantity: 10, status: "open")

      # Expect 2 restriction ranges:
      # 1. First 3 days at 200.00
      # 2. Fourth day at 300.00
      expect(client_double).to receive(:post).with("/restrictions", hash_including(
        values: [
          hash_including(date_from: start_date.to_s, date_to: end_date.to_s, rate: "200.00", stop_sell: 0),
          hash_including(date_from: diff_date.to_s, date_to: diff_date.to_s, rate: "300.00", stop_sell: 0)
        ]
      )).and_return({ "data" => { "id" => "task_2" } })

      # Wait, end_date was start_date + 2.days.
      # (start_date..end_date) is 3 days.
      # diff_date is start_date + 3.days.
      # So dates are: D0, D1, D2, D3.
      # D0-D2 have price 200.
      # D3 has price 300.
      # No gap! contiguous.
      # So 2 ranges for restrictions.

      # Expect 1 availability range because availability is same (10) and dates are contiguous
      expect(client_double).to receive(:post).with("/availability", hash_including(
        values: [
          hash_including(date_from: start_date.to_s, date_to: diff_date.to_s, availability: 10)
        ]
      )).and_return({ "data" => { "id" => "task_1" } })

      result = adapter.push_ari(date_range: (start_date..diff_date))
      expect(result.success?).to be true
    end

    it 'provides full snapshot including defaults for missing records during full sync' do
      rate_plan.room_rates.destroy_all
      room_type.room_inventories.destroy_all

      # Create only one record
      rate_plan.room_rates.create!(date: start_date, price: 250.0, currency: "MYR", room_type: room_type, stop_sell: true)
      room_type.room_inventories.create!(date: start_date, quantity: 5, status: "open")

      # Range: start_date..start_date + 1.day
      expect(client_double).to receive(:post).with("/availability", {
        values: [
          { property_id: "ch_prop_123", room_type_id: "ch_rt_123", date_from: start_date.to_s, date_to: start_date.to_s, availability: 5 },
          { property_id: "ch_prop_123", room_type_id: "ch_rt_123", date_from: (start_date + 1.day).to_s, date_to: (start_date + 1.day).to_s, availability: 0 }
        ]
      }).and_return({ "data" => { "id" => "task_1" } })

      expect(client_double).to receive(:post).with("/restrictions", {
        values: [
          {
            property_id: "ch_prop_123",
            rate_plan_id: "ch_rp_123",
            date_from: start_date.to_s,
            date_to: start_date.to_s,
            rate: "250.00",
            min_stay_arrival: 1,
            max_stay_arrival: 999,
            closed_to_arrival: 0,
            closed_to_departure: 0,
            stop_sell: 1
          },
          {
            property_id: "ch_prop_123",
            rate_plan_id: "ch_rp_123",
            date_from: (start_date + 1.day).to_s,
            date_to: (start_date + 1.day).to_s,
            min_stay_arrival: 1,
            max_stay_arrival: 999,
            closed_to_arrival: 0,
            closed_to_departure: 0,
            stop_sell: 0
          }
        ]
      }).and_return({ "data" => { "id" => "task_2" } })

      adapter.push_ari(date_range: (start_date..start_date+1.day), sync_restrictions: true, sync_rates: true, sync_availability: true)
    end
  end

  describe '#ingest_booking' do
    it 'builds full guest name from PersonName fields when available' do
      payload = {
        "data" => {
          "id" => "bk_123",
          "booking_id" => "bk_123",
          "status" => "new",
          "arrival_date" => Date.current.to_s,
          "departure_date" => (Date.current + 1.day).to_s,
          "amount" => "100.00",
          "currency" => "MYR",
          "customer" => {
            "name" => "John",
            "PersonName" => {
              "GivenName" => "John",
              "Surname" => "Doe"
            }
          },
          "rooms" => []
        }
      }

      result = adapter.ingest_booking(payload: payload)

      expect(result[:guest_details][:name]).to eq("John Doe")
    end
  end

  describe "#push_booking" do
    it "records the channel reference revision in the booking history" do
      rate_plan = create(:rate_plan, hotel: hotel, room_type: room_type)
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan)
      hotel.create_channel_mapping!(provider: "channex", external_id: "ch_prop_123")
      room_type.create_channel_mapping!(provider: "channex", external_id: "ch_rt_123")
      room_type.room_type_rate_plans.find_by!(rate_plan: rate_plan).create_channel_mapping!(provider: "channex", external_id: "ch_rp_123")
      allow(client_double).to receive(:post).and_return(
        { "data" => { "id" => "ch_booking_123", "revision_id" => 7 } }
      )

      result = adapter.push_booking(booking)

      expect(result.success?).to be(true)
      expect(BookingAuditLog.where(auditable: booking).last).to have_attributes(
        action_type: "external_modification",
        source: "channel_manager"
      )
    end
  end
end
