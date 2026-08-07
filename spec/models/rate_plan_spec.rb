require 'rails_helper'

RSpec.describe RatePlan, type: :model do
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
    it { should validate_inclusion_of(:sell_mode).in_array(%w[per_room per_person]) }
    it { should validate_presence_of(:currency) }
    it { should validate_inclusion_of(:kind).in_array(RatePlan::KINDS) }
  end

  describe 'kind' do
    let(:hotel) { create(:hotel) }

    it 'defaults to custom so a hotelier-created plan stays editable' do
      expect(RatePlan.new.kind).to eq('custom')
    end

    it 'reports special_tier_kind for each tier and nil otherwise' do
      expect(build(:rate_plan, :walk_in_tier).special_tier_kind).to eq(:walk_in)
      expect(build(:rate_plan, :corporate_tier).special_tier_kind).to eq(:corporate)
      expect(build(:rate_plan, :ota_tier).special_tier_kind).to eq(:ota)
      expect(build(:rate_plan).special_tier_kind).to be_nil
      expect(build(:rate_plan, :custom).special_tier_kind).to be_nil
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

      expect(plan.special_tier?).to be false
      expect(plan.archivable?).to be true
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
    it 'is true for a per_room plan and false for a per_person one' do
      expect(create(:rate_plan, hotel: create(:hotel))).to be_channex_syncable
      expect(create(:rate_plan, hotel: create(:hotel, :per_person))).not_to be_channex_syncable
    end
  end

  describe '.publicly_bookable' do
    let(:hotel) { create(:hotel) }

    it 'excludes special tiers and archived plans, keeping standard and custom' do
      standard = create(:rate_plan, hotel: hotel)
      custom = create(:rate_plan, :custom, hotel: hotel)
      create(:rate_plan, :walk_in_tier, hotel: hotel)
      create(:rate_plan, :corporate_tier, hotel: hotel)
      create(:rate_plan, :ota_tier, hotel: hotel)
      archived = create(:rate_plan, :custom, hotel: hotel, name: 'Old Promo')
      archived.archive!

      expect(hotel.rate_plans.publicly_bookable).to match_array([ standard, custom ])
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

    it 'is not archivable for the standard rate plan' do
      rate_plan = create(:rate_plan, hotel: hotel, name: 'Standard Rate')
      expect(rate_plan.archivable?).to be false
    end

    it 'is not archivable for a special-tier plan' do
      rate_plan = create(:rate_plan, :walk_in_tier, hotel: hotel)
      expect(rate_plan.archivable?).to be false
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
    it 'does not enqueue a sync job for a plan at a per-person hotel' do
      hotel = create(:hotel, :per_person, preferred_channel_manager: 'channex')

      expect {
        create(:rate_plan, hotel: hotel)
      }.not_to have_enqueued_job(ChannelManagers::SyncStructureJob)
    end

    it 'enqueues a sync job for a plan at a per-room hotel' do
      hotel = create(:hotel, preferred_channel_manager: 'channex')

      expect {
        create(:rate_plan, hotel: hotel)
      }.to have_enqueued_job(ChannelManagers::SyncStructureJob)
    end
  end
end
