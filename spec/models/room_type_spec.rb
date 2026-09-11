require 'rails_helper'

RSpec.describe RoomType, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:hotel) }
    it { is_expected.to have_many(:room_rates).dependent(:destroy) }
    it { is_expected.to have_many(:room_inventories).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_presence_of(:max_adults) }
    it { is_expected.to validate_numericality_of(:max_adults).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:max_children).only_integer.is_greater_than_or_equal_to(0) }

    it "defaults missing child capacity to zero" do
      room_type = build(:room_type, max_children: nil)

      room_type.validate

      expect(room_type.max_children).to eq(0)
    end
    it { is_expected.to validate_presence_of(:base_price) }
    it { is_expected.to validate_numericality_of(:base_price).is_greater_than_or_equal_to(0) }

    it "allows quantity-only inventory without room numbers" do
      expect(build(:room_type, hotel: create(:hotel), quantity: 3, room_numbers: [])).to be_valid
    end

    it "requires one unique room number per room when numbering is used" do
      duplicate = build(:room_type, quantity: 2, room_numbers: [ "101", "101" ])
      short = build(:room_type, quantity: 3, room_numbers: [ "101", "102" ])

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:room_numbers]).to include("must be unique")
      expect(short).not_to be_valid
      expect(short.errors[:room_numbers]).to include("must include exactly one number for each room")
    end
  end

  describe '#standard_rate_plan' do
    let(:hotel) { create(:hotel) }
    let(:room_type) { create(:room_type, hotel: hotel) }

    it 'returns the plan created with the category' do
      expect(room_type.standard_rate_plan).to eq(room_type.rate_plans.find_by!(kind: "standard"))
      expect(room_type.rate_plans.pluck(:kind)).to contain_exactly("standard", "walk_in", "corporate")
    end

    it 'creates the plan in the hotel’s own sell mode' do
      pax_room_type = create(:room_type, hotel: create(:hotel, :per_person))

      expect(pax_room_type.standard_rate_plan.sell_mode).to eq('per_person')
    end

    it 'ignores a plan shared in from another category' do
      anchor = room_type.standard_rate_plan
      create(:rate_plan, :custom, hotel: hotel, name: "All Inclusive Package", room_type: room_type)

      expect(room_type.reload.standard_rate_plan).to eq(anchor)
    end

    it 'ignores special tiers regardless of their id order' do
      anchor = room_type.standard_rate_plan
      create(:rate_plan, :walk_in_tier, hotel: hotel, room_type: room_type)
      create(:rate_plan, :corporate_tier, hotel: hotel, room_type: room_type)

      expect(room_type.reload.standard_rate_plan).to eq(anchor)
    end

    it 'falls back to the oldest plan when no plan is marked standard' do
      room_type.standard_rate_plan.update!(kind: "custom", name: "Base Rate")
      renamed_anchor = room_type.reload.rate_plans.find_by!(name: "Base Rate")
      create(:rate_plan, :custom, hotel: hotel, name: "Later Plan", room_type: room_type)

      expect(room_type.reload.standard_rate_plan).to eq(renamed_anchor)
    end

    # The booking paths only ever offer active plans. If the anchor resolved to
    # an archived one, pricing and restrictions would be read off a plan no
    # guest can be sold — the two halves would disagree about what is in force.
    # The archived plan is the newer one, so without the filter it would win on
    # id and the anchor would resolve to a plan nothing else will sell.
    it 'skips an archived standard plan' do
      anchor = room_type.standard_rate_plan
      newer = create(:rate_plan, hotel: hotel, name: "House Rate", room_type: room_type)
      newer.update_columns(archived_at: Time.current)

      expect(room_type.reload.standard_rate_plan).to eq(anchor)
    end

    it 'skips an archived walk-in plan' do
      room_type.walk_in_rate_plan.update_columns(archived_at: Time.current)

      expect(room_type.reload.walk_in_rate_plan).to be_nil
    end

    # AvailabilityService and the rates calendar both preload :rate_plans and
    # resolve the anchor per category, so a query here is a query per category.
    it 'does not query when rate_plans is already loaded' do
      room_type
      loaded = RoomType.includes(:rate_plans).find(room_type.id)

      queries = []
      subscriber = ->(_name, _start, _finish, _id, payload) do
        queries << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        loaded.standard_rate_plan
      end

      expect(queries).to be_empty
    end
  end

  describe "system rate plans" do
    it "creates active dedicated Standard, Walk-in, and Corporate plans" do
      room_type = create(:room_type)

      expect(room_type.rate_plans.active.pluck(:kind)).to contain_exactly("standard", "walk_in", "corporate")
      expect(room_type.rate_plans.map { |plan| plan.room_types.sole }).to all(eq(room_type))
    end

    it "initializes Walk-in and Corporate at the Standard price" do
      room_type = create(:room_type)

      expect(room_type.room_type_rate_plans.where(rate_plan: [ room_type.walk_in_rate_plan, room_type.corporate_rate_plan ]))
        .to all(have_attributes(pricing_mode: "multiplier", pricing_value: 0.to_d))
    end

    it "is idempotent" do
      room_type = create(:room_type)

      expect { RatePlans::EnsureSystemPlans.call!(room_type: room_type) }
        .not_to change { [ RatePlan.count, RoomTypeRatePlan.count ] }
    end

    it "creates a dedicated plan instead of adopting a shared legacy system plan" do
      hotel = create(:hotel)
      first_room = create(:room_type, hotel: hotel)
      second_room = create(:room_type, hotel: hotel)
      shared_plan = first_room.corporate_rate_plan
      old_plan = second_room.corporate_rate_plan
      second_room.room_type_rate_plans.find_by!(rate_plan: old_plan).destroy!
      old_plan.destroy!
      create(:room_type_rate_plan, room_type: second_room, rate_plan: shared_plan, pricing_mode: "multiplier", pricing_value: 0)

      expect { RatePlans::EnsureSystemPlans.call!(room_type: second_room) }.to change(RatePlan, :count).by(1)

      expect(second_room.reload.corporate_rate_plan).not_to eq(shared_plan)
      expect(shared_plan.reload.room_types).to contain_exactly(first_room, second_room)
    end

    it "copies the per-person occupancy ladder to both selling plans" do
      room_type = create(:room_type, hotel: create(:hotel, :per_person), max_adults: 2, base_price: 90)

      [ room_type.walk_in_rate_plan, room_type.corporate_rate_plan ].each do |plan|
        assignment = room_type.room_type_rate_plans.find_by!(rate_plan: plan)
        expect(assignment).to have_attributes(pricing_mode: "fixed", pricing_value: nil)
        expect(assignment.occupancy_prices.order(:adults).pluck(:adults, :price)).to eq([
          [ 1, 90.to_d ], [ 2, 180.to_d ]
        ])
      end
    end
  end

  describe "featured photo" do
    let(:room_type) { create(:room_type) }

    def build_blob(filename)
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("photo-#{filename}"),
        filename: filename,
        content_type: "image/jpeg"
      )
    end

    def attach(*filenames)
      room_type.attach_photos_with_limit(filenames.map { |filename| build_blob(filename) })
      room_type.photos.reload
    end

    it "features the first photo, so a category with photos always has a cover" do
      attach("a.jpg", "b.jpg")

      expect(room_type.featured_photo_attachment.filename.to_s).to eq("a.jpg")
    end

    it "keeps the chosen featured photo when more photos arrive" do
      attach("a.jpg")
      room_type.update!(featured_photo_attachment_id: room_type.photos.attachments.first.id)

      attach("b.jpg")

      expect(room_type.reload.featured_photo_attachment.filename.to_s).to eq("a.jpg")
    end

    it "reads the album with the featured photo first and the rest in upload order" do
      attach("a.jpg", "b.jpg", "c.jpg")
      third = room_type.photos.attachments.order(:id).last
      room_type.update!(featured_photo_attachment_id: third.id)

      expect(room_type.reload.ordered_photo_attachments.map { |photo| photo.filename.to_s })
        .to eq([ "c.jpg", "a.jpg", "b.jpg" ])
    end

    it "refuses a photo that belongs to another category" do
      attach("a.jpg")
      other = create(:room_type, hotel: room_type.hotel)
      other.attach_photos_with_limit([ build_blob("other.jpg") ])

      room_type.featured_photo_attachment_id = other.photos.attachments.first.id

      expect(room_type).not_to be_valid
      expect(room_type.errors[:featured_photo_attachment_id]).to include("must belong to this room type")
    end

    it "hands the featured slot to a remaining photo before the featured one goes" do
      attach("a.jpg", "b.jpg")
      featured = room_type.photos.attachments.order(:id).first

      room_type.promote_featured_photo_before_removing([ featured.id ])

      expect(room_type.reload.featured_photo_attachment.filename.to_s).to eq("b.jpg")
    end

    it "keeps the featured photo first and sorts the rest by the saved order" do
      attach("a.jpg", "b.jpg", "c.jpg")
      first, second, third = room_type.photos.attachments.order(:id).to_a

      room_type.reorder_photos!([ third.id, second.id ])

      expect(room_type.reload.ordered_photo_attachments.map(&:id))
        .to eq([ first.id, third.id, second.id ])
    end

    it "never stores the featured photo, so featuring another one keeps the order" do
      attach("a.jpg", "b.jpg", "c.jpg")
      first, second, third = room_type.photos.attachments.order(:id).to_a

      room_type.reorder_photos!([ first.id, third.id, second.id ])

      expect(room_type.photo_order).to eq([ third.id, second.id ])
    end

    it "drops ids that do not belong to the category" do
      attach("a.jpg", "b.jpg", "c.jpg")
      _first, second, third = room_type.photos.attachments.order(:id).to_a

      room_type.reorder_photos!([ third.id, 999_999, second.id ])

      expect(room_type.reload.photo_order).to eq([ third.id, second.id ])
    end

    it "puts photos uploaded after the last save at the end" do
      attach("a.jpg", "b.jpg", "c.jpg")
      first, second, third = room_type.photos.attachments.order(:id).to_a
      room_type.reorder_photos!([ third.id, second.id ])

      attach("d.jpg")
      fourth = room_type.photos.attachments.order(:id).last

      expect(room_type.reload.ordered_photo_attachments.map(&:id))
        .to eq([ first.id, third.id, second.id, fourth.id ])
    end

    it "clears the featured photo when every photo goes" do
      attach("a.jpg", "b.jpg")

      room_type.promote_featured_photo_before_removing(room_type.photos.attachments.map(&:id))

      expect(room_type.reload.featured_photo_attachment_id).to be_nil
    end
  end
end
