require 'rails_helper'

RSpec.describe RatePlan, type: :model do
  include ActiveJob::TestHelper

  describe 'associations' do
    it { should belong_to(:hotel) }
    it { should have_many(:room_type_rate_plans).dependent(:destroy) }
    it { should have_many(:room_types).through(:room_type_rate_plans) }
    it { should have_many(:room_rates).dependent(:destroy) }
    it { should have_many(:rate_plan_age_bands).dependent(:destroy) }
    it { should have_one(:channel_mapping).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:sell_mode) }

    it 'allows nil or zero Channex child fees but rejects negative values' do
      plan = build(:rate_plan, hotel: create(:hotel), channex_children_fee: 0, channex_infant_fee: nil)
      expect(plan).to be_valid

      plan.channex_infant_fee = -0.01
      expect(plan).not_to be_valid
      expect(plan.errors[:channex_infant_fee]).to be_present
    end
    it { should validate_inclusion_of(:sell_mode).in_array(%w[per_room per_person]) }
    it { should validate_presence_of(:currency) }
    it { should validate_inclusion_of(:kind).in_array(RatePlan::KINDS) }
  end

  describe 'kind' do
    let(:hotel) { create(:hotel) }

    it 'defaults to custom so a hotelier-created plan stays editable' do
      expect(RatePlan.new.kind).to eq('custom')
    end

    it 'reports which kinds read their restrictions off the anchor' do
      expect(build(:rate_plan, :walk_in_tier)).to be_anchored
      expect(build(:rate_plan, :corporate_tier)).to be_anchored
      expect(build(:rate_plan, :ota_tier)).not_to be_anchored
      expect(build(:rate_plan)).not_to be_anchored
      expect(build(:rate_plan, :custom)).not_to be_anchored
    end

    # The whole point of the column: identity used to be string-matched off the
    # name, so a rename silently changed whether a plan could be deleted.
    it 'keeps a system plan protected after it is renamed' do
      plan = create(:rate_plan, hotel: hotel)
      plan.update!(name: 'House Rate')

      expect(plan.standard_rate?).to be true
      expect(plan.archivable?).to be false
      expect(plan.deletable?).to be false
    end

    it 'does not promote an ordinary plan by naming it after a tier' do
      plan = create(:rate_plan, hotel: hotel, name: 'Corporate Rate', kind: 'custom')

      expect(plan).not_to be_anchored
      expect(plan.archivable?).to be true
      expect(plan.bookable_by?(:public)).to be true
    end
  end

  describe '#inherit_sell_mode_from_hotel' do
    let(:hotel) { create(:hotel, :per_person) }

    it 'takes the hotel’s mode on create' do
      expect(create(:rate_plan, hotel: hotel).sell_mode).to eq('per_person')
    end

    it 'ignores a sell_mode passed in directly' do
      rate_plan = create(:rate_plan, hotel: hotel, sell_mode: 'per_room')

      expect(rate_plan.sell_mode).to eq('per_person')
    end

    it 'applies to special tiers and the standard rate — nothing is exempt' do
      standard = create(:rate_plan, hotel: hotel)
      walk_in = create(:rate_plan, :walk_in_tier, hotel: hotel)

      expect(standard.sell_mode).to eq('per_person')
      expect(walk_in.sell_mode).to eq('per_person')
    end

    it 're-asserts the hotel’s mode on update' do
      rate_plan = create(:rate_plan, :custom, hotel: hotel)

      rate_plan.update!(sell_mode: 'per_room', name: 'Bed & Breakfast')

      expect(rate_plan.reload.sell_mode).to eq('per_person')
    end

    it 'follows a per_room hotel' do
      expect(create(:rate_plan, hotel: create(:hotel)).sell_mode).to eq('per_room')
    end
  end

  describe '#channex_syncable?' do
    def add_occupancy_ladder(assignment, through: assignment.room_type.max_adults)
      (1..through).each do |adults|
        assignment.occupancy_prices.create!(adults: adults, price: 100 + adults)
      end
    end

    it 'supports every distributable per-room kind' do
      hotel = create(:hotel)
      room_type = create(:room_type, hotel: hotel)

      %w[standard custom ota].each do |kind|
        plan = create(:rate_plan, hotel: hotel, room_type: room_type, kind: kind, name: "#{kind} plan")
        expect(plan.channex_capability.status).to eq(:full)
      end
    end

    it 'keeps internal and incomplete plans out of channel distribution' do
      hotel = create(:hotel, :per_person)
      room_type = create(:room_type, hotel: hotel, max_adults: 3)
      plan = create(:rate_plan, hotel: hotel, room_type: room_type)
      assignment = plan.room_type_rate_plans.find_by!(room_type: room_type)
      add_occupancy_ladder(assignment, through: 2)

      expect(plan.channex_capability(room_type: room_type)).to have_attributes(
        status: :unsupported,
        missing_occupancies: { room_type.id => [ 3 ] }
      )
      expect(create(:rate_plan, :walk_in_tier, hotel: hotel)).not_to be_channex_syncable
      expect(create(:rate_plan, :corporate_tier, hotel: hotel)).not_to be_channex_syncable
    end

    it 'supports a complete per-person occupancy ladder' do
      hotel = create(:hotel, :per_person)
      room_type = create(:room_type, hotel: hotel, max_adults: 3)
      plan = create(:rate_plan, hotel: hotel, room_type: room_type)
      add_occupancy_ladder(plan.room_type_rate_plans.find_by!(room_type: room_type))

      expect(plan.channex_capability(room_type: room_type).status).to eq(:full)
      expect(plan.channex_syncable?(room_type: room_type)).to be(true)
    end

    it 'supports a derived per-person ladder when every standard occupancy can resolve' do
      hotel = create(:hotel, :per_person)
      room_type = create(:room_type, hotel: hotel, max_adults: 3)
      standard = room_type.standard_rate_plan
      standard_assignment = standard.room_type_rate_plans.find_by!(room_type: room_type)
      add_occupancy_ladder(standard_assignment)
      plan = create(:rate_plan, :custom, hotel: hotel)
      create(
        :room_type_rate_plan,
        room_type: room_type,
        rate_plan: plan,
        pricing_mode: 'multiplier',
        pricing_value: 10
      )

      expect(plan.channex_capability(room_type: room_type).status).to eq(:full)
    end

    it 'requires explicit child and infant fees for age-banded plans and accepts zero' do
      hotel = create(:hotel, :per_person)
      room_type = create(:room_type, hotel: hotel, max_adults: 2)
      plan = create(:rate_plan, :age_banded, hotel: hotel, room_type: room_type)
      add_occupancy_ladder(plan.room_type_rate_plans.find_by!(room_type: room_type))

      expect(plan.channex_capability(room_type: room_type).status).to eq(:unsupported)

      plan.update!(channex_children_fee: 0, channex_infant_fee: 0)
      expect(plan.channex_capability(room_type: room_type).status).to eq(:flattened)
    end

    it 'evaluates shared plans against each room category capacity' do
      hotel = create(:hotel, :per_person)
      small = create(:room_type, hotel: hotel, max_adults: 2)
      large = create(:room_type, hotel: hotel, max_adults: 4)
      plan = create(:rate_plan, hotel: hotel)
      small_assignment = create(:room_type_rate_plan, room_type: small, rate_plan: plan)
      large_assignment = create(:room_type_rate_plan, room_type: large, rate_plan: plan)
      add_occupancy_ladder(small_assignment)
      add_occupancy_ladder(large_assignment, through: 3)

      expect(plan.channex_capability(room_type: small).status).to eq(:full)
      expect(plan.channex_capability(room_type: large).missing_occupancies).to eq(large.id => [ 4 ])
      expect(plan.channex_capability.status).to eq(:unsupported)
    end
  end

  describe '.for_audience' do
    let(:hotel) { create(:hotel) }
    let!(:standard) { create(:rate_plan, hotel: hotel) }
    let!(:custom) { create(:rate_plan, :custom, hotel: hotel) }
    let!(:walk_in) { create(:rate_plan, :walk_in_tier, hotel: hotel) }
    let!(:corporate) { create(:rate_plan, :corporate_tier, hotel: hotel) }

    before do
      create(:rate_plan, :ota_tier, hotel: hotel)
      create(:rate_plan, :custom, hotel: hotel, name: 'Old Promo').archive!
    end

    it 'offers the public only standard and custom' do
      expect(hotel.rate_plans.for_audience(:public)).to match_array([ standard, custom ])
    end

    it 'adds the corporate plan for a negotiated booking' do
      expect(hotel.rate_plans.for_audience(:corporate)).to match_array([ standard, custom, corporate ])
    end

    it 'adds walk-in for the front desk' do
      expect(hotel.rate_plans.for_audience(:staff)).to match_array([ standard, custom, walk_in, corporate ])
    end

    # ota is distribution-only — it is carried to the channel manager but is not
    # something any desk here can sell.
    it 'never offers an ota plan, and never an archived one' do
      RatePlan::AUDIENCE_KINDS.each_key do |audience|
        expect(hotel.rate_plans.for_audience(audience).pluck(:kind)).not_to include('ota')
        expect(hotel.rate_plans.for_audience(audience).map(&:name)).not_to include('Old Promo')
      end
      expect(RatePlan::DISTRIBUTABLE_KINDS).to include('ota')
    end
  end

  describe 'archiving' do
    let(:hotel) { create(:hotel) }

    it 'is not archived by default' do
      rate_plan = create(:rate_plan, hotel: hotel, name: 'Non-Refundable', kind: 'custom')
      expect(rate_plan.archived?).to be false
    end

    it 'archives and unarchives a custom rate plan' do
      rate_plan = create(:rate_plan, hotel: hotel, name: 'Non-Refundable', kind: 'custom')

      rate_plan.archive!
      expect(rate_plan.archived?).to be true
      expect(rate_plan.archived_at).to be_present

      rate_plan.unarchive!
      expect(rate_plan.archived?).to be false
      expect(rate_plan.archived_at).to be_nil
    end

    it 'is archivable for a custom rate plan' do
      rate_plan = create(:rate_plan, hotel: hotel, name: 'Non-Refundable', kind: 'custom')
      expect(rate_plan.archivable?).to be true
    end

    # Every other plan resolves its price against the standard plan, walk-in and
    # corporate read their restrictions off it, and the booking paths fall back
    # to it. Archiving it leaves the room category unsellable.
    it 'is not archivable for the standard rate plan' do
      rate_plan = create(:rate_plan, hotel: hotel, name: 'Standard Rate')
      expect(rate_plan.archivable?).to be false
    end

    it 'is archivable for a special-tier plan' do
      rate_plan = create(:rate_plan, :walk_in_tier, hotel: hotel)
      expect(rate_plan.archivable?).to be true
    end

    it 'archives and restores system plans without making them deletable' do
      rate_plan = create(:rate_plan, :corporate_tier, hotel: hotel)

      rate_plan.archive!
      expect(rate_plan).to be_archived
      expect(rate_plan).not_to be_deletable

      rate_plan.unarchive!
      expect(rate_plan).not_to be_archived
    end

    it 'scopes .active to non-archived plans and .archived to archived plans' do
      active_plan = create(:rate_plan, hotel: hotel, name: 'Room Only', kind: 'custom')
      archived_plan = create(:rate_plan, hotel: hotel, name: 'Non-Refundable', kind: 'custom')
      archived_plan.archive!

      expect(RatePlan.active).to include(active_plan)
      expect(RatePlan.active).not_to include(archived_plan)
      expect(RatePlan.archived).to include(archived_plan)
      expect(RatePlan.archived).not_to include(active_plan)
    end
  end

  describe '#age_banded?' do
    it 'is false for a per_room rate plan even with bands present' do
      rate_plan = create(:rate_plan, hotel: create(:hotel))
      create(:rate_plan_age_band, rate_plan: rate_plan)

      expect(rate_plan.age_banded?).to be false
    end

    it 'is false for a per_person rate plan with no bands configured' do
      rate_plan = create(:rate_plan, hotel: create(:hotel, :per_person))

      expect(rate_plan.age_banded?).to be false
    end

    it 'is true for a per_person rate plan with bands configured' do
      rate_plan = create(:rate_plan, hotel: create(:hotel, :per_person))
      create(:rate_plan_age_band, rate_plan: rate_plan)

      expect(rate_plan.age_banded?).to be true
    end
  end

  describe '#band_for_age' do
    let(:hotel) { create(:hotel, :per_person) }
    let(:rate_plan) { create(:rate_plan, :age_banded, hotel: hotel) }

    it 'resolves the band covering the given age' do
      expect(rate_plan.band_for_age(6).label).to eq('Child')
      expect(rate_plan.band_for_age(15).label).to eq('Teen')
    end

    it 'returns nil for an age not covered by any band' do
      expect(rate_plan.band_for_age(30)).to be_nil
    end
  end

  describe '#sync_with_channel_manager' do
    it 'queues retirement reconciliation but no structure sync for an unsupported assignment' do
      hotel = create(:hotel, :per_person, preferred_channel_manager: 'channex')
      create(:channel_mapping, mappable: hotel)
      room_type = create(:room_type, hotel: hotel, max_adults: 2)
      clear_enqueued_jobs

      create(:rate_plan, hotel: hotel, room_type: room_type)

      expect(enqueued_jobs.none? { |job| job[:job] == ChannelManagers::SyncStructureJob }).to be(true)
      expect(enqueued_jobs.count { |job| job[:job] == ChannelManagers::SyncJob }).to eq(1)
    end

    it 'enqueues structure and ARI syncs for a compatible assignment' do
      hotel = create(:hotel, preferred_channel_manager: 'channex')
      create(:channel_mapping, mappable: hotel)
      room_type = create(:room_type, hotel: hotel)
      clear_enqueued_jobs

      create(:rate_plan, hotel: hotel, room_type: room_type)

      expect(enqueued_jobs.count { |job| job[:job] == ChannelManagers::SyncStructureJob }).to eq(1)
      expect(enqueued_jobs.count { |job| job[:job] == ChannelManagers::SyncJob }).to eq(1)
    end
  end
end
