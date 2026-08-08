require "rails_helper"

RSpec.describe HotelOps::ApplyInventoryDashboardSelection do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:user) { create(:user, account: hotel.account) }
  let(:start_date) { Date.current }
  let(:end_date) { Date.current + 1.day }

  before do
    allow(ChannelManagers::SyncJob).to receive(:perform_later)
  end

  describe "#call" do
    it "updates inventory across multiple room types" do
      deluxe = create(:room_type, hotel: hotel, quantity: 5)
      twin = create(:room_type, hotel: hotel, quantity: 3)

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: end_date,
          room_type_ids: [ deluxe.id, twin.id ],
          apply_inventory: "1",
          quantity: "2",
          status: "open"
        },
        user: user
      ).call

      expect(result[:success]).to be(true)
      expect(deluxe.room_inventories.find_by(date: start_date).quantity).to eq(2)
      expect(twin.room_inventories.find_by(date: end_date).quantity).to eq(2)
    end

    it "updates rates across multiple selected rate plans" do
      room_type = create(:room_type, hotel: hotel, base_price: 100)
      best_available = create(:rate_plan, room_type: room_type, name: "Best Available")
      member_rate = create(:rate_plan, room_type: room_type, name: "Member Rate")

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ best_available.id, member_rate.id ],
          apply_rates: "1",
          price: "333.00",
          currency: "MYR"
        },
        user: user
      ).call

      expect(result[:success]).to be(true)
      expect(best_available.room_rates.find_by(date: start_date, currency: "MYR").price.to_f).to eq(333.0)
      expect(member_rate.room_rates.find_by(date: start_date, currency: "MYR").price.to_f).to eq(333.0)
    end

    it "stores date-specific prices for each supported adult occupancy" do
      hotel.update!(sell_mode: "per_person")
      room_type = create(:room_type, hotel: hotel, max_adults: 2, base_price: 100)
      rate_plan = create(:rate_plan, :custom, hotel: hotel, room_type: room_type)

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ rate_plan.id ],
          apply_rates: "1",
          modified_fields: [ "occupancy_prices" ],
          occupancy_prices: { "1" => "180.00", "2" => "300.00" },
          currency: "MYR"
        },
        user: user
      ).call

      expect(result[:success]).to be(true)
      rate = rate_plan.room_rates.find_by!(room_type: room_type, date: start_date, currency: "MYR")
      expect(rate.occupancy_prices).to eq("1" => "180.0", "2" => "300.0")
      expect(rate.price).to eq(300.to_d)
    end

    it "writes rate updates in the requested currency and updates the rate plan currency" do
      room_type = create(:room_type, hotel: hotel, base_price: 100)
      jpy_plan = create(:rate_plan, room_type: room_type, currency: "JPY")

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ jpy_plan.id ],
          apply_rates: "1",
          price: "12000",
          currency: "USD"
        },
        user: user
      ).call

      expect(result[:success]).to be(true)
      expect(jpy_plan.reload.currency).to eq("USD")
      expect(jpy_plan.room_rates.find_by(date: start_date, currency: "USD").price.to_f).to eq(12000.0)
    end

    it "applies restrictions without requiring a rate override" do
      room_type = create(:room_type, hotel: hotel, base_price: 220)
      rate_plan = create(:rate_plan, room_type: room_type)

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ rate_plan.id ],
          apply_restrictions: "1",
          min_stay: "2",
          max_stay: "5",
          closed_to_arrival: "1",
          closed_to_departure: "0",
          stop_sell: "1",
          currency: "MYR"
        },
        user: user
      ).call

      expect(result[:success]).to be(true)
      rate = rate_plan.room_rates.find_by(date: start_date, currency: "MYR")
      expect(rate.price.to_f).to eq(220.0)
      expect(rate.min_stay).to eq(2)
      expect(rate.max_stay).to eq(5)
      expect(rate.closed_to_arrival).to be(true)
      expect(rate.closed_to_departure).to be(false)
      expect(rate.stop_sell).to be(true)
    end

    it "applies restrictions across MYR and USD regardless of selected currency" do
      room_type = create(:room_type, hotel: hotel, base_price: 220)
      rate_plan = create(:rate_plan, room_type: room_type)

      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: start_date, currency: "MYR", price: 220)
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: start_date, currency: "USD", price: 55)

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ rate_plan.id ],
          apply_restrictions: "1",
          min_stay: "1",
          max_stay: "3",
          closed_to_arrival: "1",
          closed_to_departure: "1",
          stop_sell: "1",
          currency: "USD"
        },
        user: user
      ).call

      expect(result[:success]).to be(true)

      myr_rate = rate_plan.room_rates.find_by(date: start_date, currency: "MYR")
      usd_rate = rate_plan.room_rates.find_by(date: start_date, currency: "USD")

      [ myr_rate, usd_rate ].each do |rate|
        expect(rate.min_stay).to eq(1)
        expect(rate.max_stay).to eq(3)
        expect(rate.closed_to_arrival).to be(true)
        expect(rate.closed_to_departure).to be(true)
        expect(rate.stop_sell).to be(true)
      end
    end

    it "derives inventory quantity from selected room numbers for one room type" do
      room_type = create(:room_type, hotel: hotel, quantity: 3, room_numbers: %w[101 102 103])

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          apply_inventory: "1",
          status: "open",
          available_room_numbers: %w[101 103]
        },
        user: user
      ).call

      expect(result[:success]).to be(true)
      inventory = room_type.room_inventories.find_by(date: start_date)
      expect(inventory.quantity).to eq(2)
      expect(inventory.available_room_numbers).to match_array(%w[101 103])
    end

    it "triggers a single sync job for one applied selection" do
      room_type = create(:room_type, hotel: hotel)

      described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: end_date,
          room_type_ids: [ room_type.id ],
          apply_inventory: "1",
          apply_rates: "0",
          apply_restrictions: "0",
          quantity: "1",
          status: "closed"
        },
        user: user
      ).call

      expect(ChannelManagers::SyncJob).to have_received(:perform_later).once.with(
        hotel.id,
        start_date,
        end_date,
        sync_availability: true,
        sync_rates: false,
        sync_restrictions: false
      )
    end

    it "updates only the corporate price when only corporate tier is selected" do
      room_type = create(:room_type, hotel: hotel, base_price: 100)
      rate_plan = room_type.rate_plans.first # Use auto-created plan
      # Pre-create a rate record with some standard price
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: start_date, currency: "MYR", price: 150)

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ "tier_corporate_#{room_type.id}" ],
          apply_rates: "1",
          price: "200.00",
          currency: "MYR"
        },
        user: user
      ).call

      expect(result[:success]).to be(true)
      rate = rate_plan.room_rates.find_by(date: start_date, currency: "MYR")
      expect(rate.corporate_price.to_f).to eq(200.0)
      expect(rate.price.to_f).to eq(150.0) # Standard price should REMAIN unchanged
    end

    it "updates only the standard price when only standard plan is selected" do
      room_type = create(:room_type, hotel: hotel, base_price: 100)
      rate_plan = room_type.rate_plans.first # Use auto-created plan
      # Pre-create a rate record with some corporate price
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: start_date, currency: "MYR", price: 150, corporate_price: 200)

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ rate_plan.id ],
          apply_rates: "1",
          price: "180.00",
          currency: "MYR"
        },
        user: user
      ).call

      expect(result[:success]).to be(true)
      rate = rate_plan.room_rates.find_by(date: start_date, currency: "MYR")
      expect(rate.price.to_f).to eq(180.0)
      expect(rate.corporate_price.to_f).to eq(200.0) # Corporate price should REMAIN unchanged
    end



    it "updates base_occupancy, extra_pax_charge, and single_supplement when rates are modified" do
      room_type = create(:room_type, hotel: hotel, base_price: 100)
      rate_plan = room_type.rate_plans.first

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ rate_plan.id ],
          apply_rates: "1",
          base_occupancy: "3",
          extra_pax_charge: "60.00",
          single_supplement: "30.00",
          currency: "MYR"
        },
        user: user
      ).call

      expect(result[:success]).to be(true)
      rate = rate_plan.room_rates.find_by(date: start_date, currency: "MYR")
      expect(rate.base_occupancy).to eq(3)
      expect(rate.extra_pax_charge.to_f).to eq(60.0)
      expect(rate.single_supplement.to_f).to eq(30.0)
    end

    it "creates channel overrides in channel_room_rates table when channel_id is present" do
      room_type = create(:room_type, hotel: hotel, base_price: 100)
      rate_plan = room_type.rate_plans.first

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ rate_plan.id ],
          apply_rates: "1",
          price: "150.00",
          channel_id: "booking_com",
          channel_rate_plan_id: "b_test_rate_plan",
          currency: "MYR"
        },
        user: user
      ).call

      expect(result[:success]).to be(true)
      override = ChannelRoomRate.find_by(
        room_type_id: room_type.id,
        rate_plan_id: rate_plan.id,
        channel_id: "booking_com",
        channel_rate_plan_id: "b_test_rate_plan",
        date: start_date
      )
      expect(override).to be_present
      expect(override.price.to_f).to eq(150.0)
    end

    it "returns a clear failure instead of raising when pax fields are combined with a channel override" do
      room_type = create(:room_type, hotel: hotel, base_price: 100)
      rate_plan = room_type.rate_plans.first

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ rate_plan.id ],
          apply_rates: "1",
          price: "150.00",
          base_occupancy: "3",
          channel_id: "booking_com",
          channel_rate_plan_id: "b_test_rate_plan",
          currency: "MYR"
        },
        user: user
      ).call

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/don't apply to OTA channel rates/)
    end

    it "returns a clear failure when modified_fields includes a pax field alongside a channel override" do
      room_type = create(:room_type, hotel: hotel, base_price: 100)
      rate_plan = room_type.rate_plans.first

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          rate_plan_ids: [ rate_plan.id ],
          apply_rates: "1",
          price: "150.00",
          modified_fields: [ "extra_pax_charge" ],
          extra_pax_charge: "20.00",
          channel_id: "booking_com",
          channel_rate_plan_id: "b_test_rate_plan",
          currency: "MYR"
        },
        user: user
      ).call

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/don't apply to OTA channel rates/)
    end

    it "creates channel availability overrides when channel_id is present for channel_availability" do
      room_type = create(:room_type, hotel: hotel, base_price: 100)

      result = described_class.new(
        hotel: hotel,
        selection: {
          start_date: start_date,
          end_date: start_date,
          room_type_ids: [ room_type.id ],
          apply_inventory: "1",
          quantity: "2",
          status: "closed",
          channel_id: "booking_com"
        },
        user: user
      ).call

      expect(result[:success]).to be(true)
      override = ChannelRoomRate.find_by(
        room_type_id: room_type.id,
        rate_plan_id: nil,
        channel_id: "booking_com",
        date: start_date
      )
      expect(override).to be_present
      expect(override.availability).to eq(2)
      expect(override.stop_sell).to be(true)
    end
    context "when a Standard Rate plan is shared across multiple room types" do
      it "does NOT affect other room types when updating only Double Room's standard rate" do
        # Reproduces bug: updating Double Room standard rate was bleeding into Executive Room
        # because find_or_initialize_by was missing room_type_id
        shared_rate_plan = create(:rate_plan, hotel: hotel, name: "Standard Rate", currency: "MYR")

        double_room = create(:room_type, hotel: hotel, base_price: 200)
        executive_room = create(:room_type, hotel: hotel, base_price: 300)

        double_room.room_type_rate_plans.create!(rate_plan: shared_rate_plan)
        executive_room.room_type_rate_plans.create!(rate_plan: shared_rate_plan)

        # Pre-seed executive room's rate so there is a record to be found first
        exec_rate = create(:room_rate, room_type: executive_room, rate_plan: shared_rate_plan,
                           date: start_date, currency: "MYR", price: 300)

        result = described_class.new(
          hotel: hotel,
          selection: {
            start_date: start_date,
            end_date: start_date,
            room_type_ids: [ double_room.id ],         # Only Double Room selected
            rate_plan_ids: [ shared_rate_plan.id ],    # Standard Rate
            apply_rates: "1",
            price: "250.00",
            currency: "MYR"
          },
          user: user
        ).call

        expect(result[:success]).to be(true)

        double_rate = shared_rate_plan.room_rates.find_by(date: start_date, currency: "MYR", room_type: double_room)
        expect(double_rate&.price.to_f).to eq(250.0), "Double Room rate should be updated to 250"

        exec_rate.reload
        expect(exec_rate.price.to_f).to eq(300.0), "Executive Room rate must NOT be changed"
      end

      it "does NOT clear walk_in_price or corporate_price when updating standard rate for a single room type" do
        shared_rate_plan = create(:rate_plan, hotel: hotel, name: "Standard Rate", currency: "MYR")
        double_room = create(:room_type, hotel: hotel, base_price: 200)
        double_room.room_type_rate_plans.create!(rate_plan: shared_rate_plan)

        existing_rate = create(
          :room_rate,
          room_type: double_room,
          rate_plan: shared_rate_plan,
          date: start_date,
          currency: "MYR",
          price: 200,
          walk_in_price: 220,
          corporate_price: 180
        )

        described_class.new(
          hotel: hotel,
          selection: {
            start_date: start_date,
            end_date: start_date,
            room_type_ids: [ double_room.id ],
            rate_plan_ids: [ shared_rate_plan.id ],
            apply_rates: "1",
            price: "250.00",
            currency: "MYR"
          },
          user: user
        ).call

        existing_rate.reload
        expect(existing_rate.price.to_f).to eq(250.0)
        expect(existing_rate.walk_in_price.to_f).to eq(220.0), "Walk-in price must NOT be touched"
        expect(existing_rate.corporate_price.to_f).to eq(180.0), "Corporate price must NOT be touched"
      end
    end

    context "with a plan that derives its price from the anchor" do
      let!(:room_type) { create(:room_type, hotel: hotel, base_price: 200) }
      let!(:package) { create(:rate_plan, :custom, hotel: hotel, currency: "MYR") }

      before do
        create(:room_type_rate_plan, rate_plan: package, room_type: room_type, pricing_mode: "multiplier", pricing_value: 20)
      end

      it "seeds a restrictions-only row at the derived price, not the anchor" do
        described_class.new(
          hotel: hotel,
          selection: {
            start_date: start_date,
            end_date: start_date,
            room_type_ids: [ room_type.id ],
            rate_plan_ids: [ package.id ],
            apply_restrictions: "1",
            min_stay: "2",
            currency: "MYR"
          },
          user: user
        ).call

        rate = package.room_rates.find_by(room_type: room_type, date: start_date)
        expect(rate.min_stay).to eq(2)
        expect(rate.price.to_f).to eq(240.0)
      end
    end

    context "with an archived rate plan" do
      let!(:room_type) { create(:room_type, hotel: hotel, base_price: 200) }
      let!(:archived) { create(:rate_plan, :custom, hotel: hotel, room_type: room_type, currency: "MYR") }

      before { archived.archive! }

      it "does not price plans that are no longer bookable" do
        described_class.new(
          hotel: hotel,
          selection: {
            start_date: start_date,
            end_date: start_date,
            room_type_ids: [ room_type.id ],
            apply_rates: "1",
            price: "500.00",
            currency: "MYR"
          },
          user: user
        ).call

        expect(archived.room_rates.where(room_type: room_type)).to be_empty
      end
    end

    context "when an OTA tier id is submitted" do
      let!(:room_type) { create(:room_type, hotel: hotel, base_price: 200) }

      it "is ignored rather than written onto the anchor's nightly price" do
        described_class.new(
          hotel: hotel,
          selection: {
            start_date: start_date,
            end_date: start_date,
            room_type_ids: [ room_type.id ],
            rate_plan_ids: [ "tier_ota_#{room_type.id}" ],
            apply_rates: "1",
            price: "999.00",
            currency: "MYR"
          },
          user: user
        ).call

        anchor_rate = room_type.standard_rate_plan.room_rates.find_by(room_type: room_type, date: start_date)
        expect(anchor_rate&.price&.to_f).not_to eq(999.0)
      end
    end
  end
end
