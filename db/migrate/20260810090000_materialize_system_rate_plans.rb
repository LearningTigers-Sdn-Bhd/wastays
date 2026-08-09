# frozen_string_literal: true

class MaterializeSystemRatePlans < ActiveRecord::Migration[8.0]
  class MigrationHotel < ActiveRecord::Base
    self.table_name = "hotels"
  end

  class MigrationRoomType < ActiveRecord::Base
    self.table_name = "room_types"
    belongs_to :hotel, class_name: "MaterializeSystemRatePlans::MigrationHotel"
  end

  class MigrationRatePlan < ActiveRecord::Base
    self.table_name = "rate_plans"
  end

  class MigrationAssignment < ActiveRecord::Base
    self.table_name = "room_type_rate_plans"
  end

  class MigrationOccupancyPrice < ActiveRecord::Base
    self.table_name = "room_type_rate_plan_occupancy_prices"
  end

  class MigrationAgeBand < ActiveRecord::Base
    self.table_name = "rate_plan_age_bands"
  end

  class MigrationRoomRate < ActiveRecord::Base
    self.table_name = "room_rates"
  end

  class MigrationBookingRoom < ActiveRecord::Base
    self.table_name = "booking_rooms"
  end

  class MigrationQuoteItem < ActiveRecord::Base
    self.table_name = "booking_quote_items"
  end

  class MigrationChannelMapping < ActiveRecord::Base
    self.table_name = "channel_mappings"
  end

  SYSTEM_NAMES = {
    "standard" => "Standard Rate",
    "walk_in" => "Walk-in Rate",
    "corporate" => "Corporate Rate"
  }.freeze

  TIER_KINDS = %w[walk_in corporate].freeze

  RATE_COPY_COLUMNS = %w[
    date currency min_stay max_stay stop_sell closed_to_arrival
    closed_to_departure applied_rule_type occupancy_prices base_occupancy
    extra_pax_charge single_supplement
  ].freeze

  def up
    plan_ids_by_room = {}

    MigrationRoomType.find_each do |room_type|
      plan_ids_by_room[room_type.id] = ensure_system_plans!(room_type)
      migrate_virtual_rates!(room_type.id, plan_ids_by_room.fetch(room_type.id))
    end

    # Order matters: a retiring plan's rows are the category's real prices and
    # outranked any unattributed row, exactly as the old readers resolved them.
    # Adopting them first lets the backfill see those dates as already claimed.
    retire_shared_system_assignments!(plan_ids_by_room)
    backfill_unattributed_rates!(plan_ids_by_room)
    migrate_historical_snapshots!(plan_ids_by_room)

    remove_column :room_rates, :walk_in_price
    remove_column :room_rates, :corporate_price
  end

  def down
    add_column :room_rates, :walk_in_price, :decimal, precision: 10, scale: 2
    add_column :room_rates, :corporate_price, :decimal, precision: 10, scale: 2

    MigrationRoomRate.reset_column_information
    MigrationRoomType.find_each do |room_type|
      standard_id = latest_attached_plan_id(room_type.id, "standard")
      next unless standard_id

      { "walk_in" => "walk_in_price", "corporate" => "corporate_price" }.each do |kind, column|
        tier_id = latest_attached_plan_id(room_type.id, kind)
        next unless tier_id

        MigrationRoomRate.where(room_type_id: room_type.id, rate_plan_id: tier_id).find_each do |tier_rate|
          standard_rate = MigrationRoomRate.find_by(
            room_type_id: room_type.id,
            rate_plan_id: standard_id,
            date: tier_rate.date,
            currency: tier_rate.currency
          )
          standard_rate&.update_columns(column => tier_rate.price)
        end
      end
    end


    restore_legacy_snapshots!
  end

  private

  def ensure_system_plans!(room_type)
    standard = ensure_plan!(room_type, "standard")
    {
      "standard" => standard.id,
      "walk_in" => ensure_plan!(room_type, "walk_in", anchor: standard).id,
      "corporate" => ensure_plan!(room_type, "corporate", anchor: standard).id
    }
  end

  def ensure_plan!(room_type, kind, anchor: nil)
    existing_id = dedicated_attached_plan_id(room_type.id, kind)
    return MigrationRatePlan.find(existing_id) if existing_id

    hotel = room_type.hotel
    source = anchor
    now = Time.current
    plan = MigrationRatePlan.create!(
      hotel_id: room_type.hotel_id,
      name: SYSTEM_NAMES.fetch(kind),
      kind: kind,
      currency: source&.currency || hotel.default_currency.presence || "MYR",
      sell_mode: hotel.sell_mode.presence || "per_room",
      base_occupancy: source&.base_occupancy || 2,
      single_supplement: source&.single_supplement || 0,
      child_price_multiplier: source&.child_price_multiplier || 1,
      extra_pax_charge: source&.extra_pax_charge || 0,
      created_at: now,
      updated_at: now
    )

    copy_age_bands!(source.id, plan.id) if source
    create_assignment!(room_type, plan, standard_id: anchor&.id)
    plan
  end

  def create_assignment!(room_type, plan, standard_id: nil)
    per_person = room_type.hotel.sell_mode == "per_person"
    now = Time.current
    assignment = MigrationAssignment.create!(
      room_type_id: room_type.id,
      rate_plan_id: plan.id,
      pricing_mode: per_person && standard_id ? "fixed" : (standard_id ? "multiplier" : "fixed"),
      pricing_value: standard_id && !per_person ? 0 : nil,
      created_at: now,
      updated_at: now
    )
    return unless per_person && standard_id

    standard_assignment_id = MigrationAssignment.find_by(room_type_id: room_type.id, rate_plan_id: standard_id)&.id
    standard_prices = MigrationOccupancyPrice.where(room_type_rate_plan_id: standard_assignment_id).index_by(&:adults)
    (1..room_type.max_adults.to_i).each do |adults|
      price = standard_prices[adults]&.price || room_type.base_price.to_d * adults
      MigrationOccupancyPrice.create!(
        room_type_rate_plan_id: assignment.id,
        adults: adults,
        price: price,
        created_at: now,
        updated_at: now
      )
    end
  end

  def copy_age_bands!(source_id, target_id)
    MigrationAgeBand.where(rate_plan_id: source_id).find_each do |band|
      attrs = band.attributes.except("id", "rate_plan_id", "created_at", "updated_at")
      MigrationAgeBand.create!(attrs.merge("rate_plan_id" => target_id, "created_at" => Time.current, "updated_at" => Time.current))
    end
  end

  def migrate_virtual_rates!(room_type_id, plan_ids)
    source_rates = MigrationRoomRate.where(room_type_id: room_type_id)
      .where("walk_in_price IS NOT NULL OR corporate_price IS NOT NULL")
      .to_a
      .sort_by { |rate| [ source_priority(rate.rate_plan_id, plan_ids.fetch("standard")), rate.id ] }

    source_rates.group_by { |rate| [ rate.date, rate.currency ] }.each_value do |candidates|
      walk_in_source = candidates.find { |rate| rate.walk_in_price.present? }
      corporate_source = candidates.find { |rate| rate.corporate_price.present? }

      migrate_tier_rate!(walk_in_source, plan_ids.fetch("walk_in"), walk_in_source.walk_in_price) if walk_in_source
      migrate_tier_rate!(corporate_source, plan_ids.fetch("corporate"), corporate_source.corporate_price) if corporate_source
    end
  end

  def migrate_tier_rate!(source, target_plan_id, price)
    target = MigrationRoomRate.find_or_initialize_by(
      room_type_id: source.room_type_id,
      rate_plan_id: target_plan_id,
      date: source.date,
      currency: source.currency
    )
    attrs = source.attributes.slice(*RATE_COPY_COLUMNS)
    target.assign_attributes(attrs.merge("price" => price, "updated_at" => Time.current))
    target.created_at ||= source.created_at || Time.current
    target.save!
  end

  # Rows predating rate_plan_id carry the category's standard price. Every
  # reader used to fall back to them when the plan's own row was missing; after
  # this migration nothing does, so an unclaimed row has to become the standard
  # plan's row or its price disappears.
  #
  # The anchor's own row outranks it, which is the same order the old fallback
  # applied — so where both exist the unattributed row is dropped rather than
  # colliding with the (room_type_id, rate_plan_id, date, currency) unique index.
  def backfill_unattributed_rates!(plan_ids_by_room)
    plan_ids_by_room.each do |room_type_id, plan_ids|
      standard_id = plan_ids.fetch("standard")

      MigrationRoomRate.where(room_type_id: room_type_id, rate_plan_id: nil).find_each do |rate|
        claimed = MigrationRoomRate.where(
          room_type_id: room_type_id,
          rate_plan_id: standard_id,
          date: rate.date,
          currency: rate.currency
        ).exists?

        if claimed
          rate.delete
        else
          rate.update_columns(rate_plan_id: standard_id, updated_at: Time.current)
        end
      end
    end
  end

  def source_priority(rate_plan_id, standard_id)
    return 0 if rate_plan_id == standard_id
    return 1 if rate_plan_id.nil?

    2
  end

  def migrate_historical_snapshots!(plan_ids_by_room)
    MigrationBookingRoom.find_each do |booking_room|
      plans = plan_ids_by_room[booking_room.room_type_id]
      next unless plans

      snapshot, tier_kinds = materialize_snapshot(booking_room.nightly_rate_snapshot, plans, booking_room.rate_plan_id)
      next if snapshot == booking_room.nightly_rate_snapshot

      attributes = { nightly_rate_snapshot: snapshot, updated_at: Time.current }
      # Only a tier sale moves the row: those bookings pointed at the anchor plan
      # while being charged the tier price, so the plan has to catch up. A
      # standard sale already points at the plan it was sold on.
      attributes[:rate_plan_id] = plans.fetch(tier_kinds.first) if tier_kinds.any?
      booking_room.update_columns(attributes)
    end

    MigrationQuoteItem.find_each do |item|
      plans = plan_ids_by_room[item.room_type_id]
      next unless plans

      snapshot, = materialize_snapshot(item.nightly_rate_snapshot, plans, nil)
      next if snapshot == item.nightly_rate_snapshot

      item.update_columns(nightly_rate_snapshot: snapshot, updated_at: Time.current)
    end
  end

  # `rate_tier` only ever distinguished a tier sale from an ordinary one — it was
  # stamped as "standard" on every entry UpdateStayService touched, whatever plan
  # the booking was actually on. So a "standard" entry resolves to the row's own
  # plan (which may well be a custom plan), never to the new dedicated Standard.
  # Returns the tier kinds found, which is what the caller keys the plan move off.
  def materialize_snapshot(snapshot, plans, own_plan_id)
    return [ snapshot, [] ] unless snapshot.is_a?(Hash)

    tier_kinds = []
    transformed = snapshot.transform_values do |entry|
      next entry unless entry.is_a?(Hash)

      kind = entry["rate_tier"].to_s
      next entry unless plans.key?(kind)

      if TIER_KINDS.include?(kind)
        tier_kinds << kind
        plan_id = plans.fetch(kind)
      else
        plan_id = own_plan_id || plans.fetch("standard")
      end

      entry.except("rate_tier").merge("rate_plan_id" => plan_id)
    end
    [ transformed, tier_kinds ]
  end

  def restore_legacy_snapshots!
    plans_by_room = MigrationRoomType.find_each.to_h do |room_type|
      [ room_type.id, SYSTEM_NAMES.keys.index_with { |kind| latest_attached_plan_id(room_type.id, kind) }.compact ]
    end

    MigrationBookingRoom.find_each do |booking_room|
      plans = plans_by_room[booking_room.room_type_id]
      next if plans.blank?

      snapshot, tier_kinds = virtualize_snapshot(booking_room.nightly_rate_snapshot, plans)
      next if snapshot == booking_room.nightly_rate_snapshot

      attributes = { nightly_rate_snapshot: snapshot, updated_at: Time.current }
      # Mirrors the up path: only a tier sale moved the plan, so only a tier sale
      # moves it back. A booking sold on a custom plan keeps pointing at it.
      attributes[:rate_plan_id] = plans["standard"] if tier_kinds.any? && plans["standard"]
      booking_room.update_columns(attributes)
    end

    MigrationQuoteItem.find_each do |item|
      plans = plans_by_room[item.room_type_id]
      next if plans.blank?

      snapshot, = virtualize_snapshot(item.nightly_rate_snapshot, plans)
      next if snapshot == item.nightly_rate_snapshot

      item.update_columns(nightly_rate_snapshot: snapshot, updated_at: Time.current)
    end
  end

  # Inverse of materialize_snapshot: every entry carrying rate_plan_id is one the
  # up path wrote, so all of them go back to a rate_tier. Anything that is not a
  # tier plan was an ordinary sale, which is what "standard" meant.
  def virtualize_snapshot(snapshot, plans)
    return [ snapshot, [] ] unless snapshot.is_a?(Hash)

    kind_by_plan_id = plans.slice(*TIER_KINDS).invert
    tier_kinds = []
    transformed = snapshot.transform_values do |entry|
      next entry unless entry.is_a?(Hash) && entry.key?("rate_plan_id")

      kind = kind_by_plan_id[entry["rate_plan_id"]]
      tier_kinds << kind if kind

      entry.except("rate_plan_id").merge("rate_tier" => kind || "standard")
    end
    [ transformed, tier_kinds ]
  end

  # A category ends up owning exactly one plan per system kind. Anything else it
  # carried — a plan shared with another category, or a second plan of the same
  # kind — is detached here.
  #
  # Detaching is not enough on its own: the retiring plan holds this category's
  # real prices, and nothing reads a detached plan afterwards. So its rows are
  # adopted onto the dedicated plan first, and the per-assignment records the
  # real model cascades (occupancy prices, channel mapping) are cleared with it.
  #
  # Note this half is one-way — `down` restores prices and snapshots, not the
  # assignments destroyed here.
  def retire_shared_system_assignments!(plan_ids_by_room)
    shared_plan_ids = MigrationAssignment
      .joins("INNER JOIN rate_plans ON rate_plans.id = room_type_rate_plans.rate_plan_id")
      .where(rate_plans: { kind: SYSTEM_NAMES.keys })
      .group(:rate_plan_id)
      .having("COUNT(*) > 1")
      .pluck(:rate_plan_id)

    plan_ids_by_room.each do |room_type_id, dedicated_ids|
      retiring = MigrationAssignment.where(room_type_id: room_type_id)
        .joins("INNER JOIN rate_plans ON rate_plans.id = room_type_rate_plans.rate_plan_id")
        .where(rate_plans: { kind: SYSTEM_NAMES.keys })
        .where.not(rate_plan_id: dedicated_ids.values)
        .pluck("room_type_rate_plans.id", "room_type_rate_plans.rate_plan_id", "rate_plans.kind")

      retiring.each do |assignment_id, rate_plan_id, kind|
        adopt_retired_rates!(room_type_id, rate_plan_id, dedicated_ids.fetch(kind))
        MigrationOccupancyPrice.where(room_type_rate_plan_id: assignment_id).delete_all
        MigrationChannelMapping.where(mappable_type: "RoomTypeRatePlan", mappable_id: assignment_id).delete_all
        MigrationAssignment.where(id: assignment_id).delete_all
      end
    end

    MigrationRatePlan.where(id: shared_plan_ids, archived_at: nil)
      .update_all(archived_at: Time.current, updated_at: Time.current)
  end

  # Same precedence as the unattributed backfill: the dedicated plan's own row
  # wins, because that is the row every reader resolves to from here on.
  def adopt_retired_rates!(room_type_id, retiring_plan_id, dedicated_plan_id)
    MigrationRoomRate.where(room_type_id: room_type_id, rate_plan_id: retiring_plan_id).find_each do |rate|
      claimed = MigrationRoomRate.where(
        room_type_id: room_type_id,
        rate_plan_id: dedicated_plan_id,
        date: rate.date,
        currency: rate.currency
      ).exists?

      if claimed
        rate.delete
      else
        rate.update_columns(rate_plan_id: dedicated_plan_id, updated_at: Time.current)
      end
    end
  end

  # Newest wins, matching RoomType#system_rate_plan — otherwise the migration
  # would adopt one plan and the app would then resolve to a different one.
  def dedicated_attached_plan_id(room_type_id, kind)
    MigrationAssignment.joins("INNER JOIN rate_plans ON rate_plans.id = room_type_rate_plans.rate_plan_id")
      .where(room_type_id: room_type_id, rate_plans: { kind: kind })
      .where(rate_plan_id: MigrationAssignment.group(:rate_plan_id).having("COUNT(*) = 1").select(:rate_plan_id))
      .maximum(:rate_plan_id)
  end

  def latest_attached_plan_id(room_type_id, kind)
    MigrationAssignment.joins("INNER JOIN rate_plans ON rate_plans.id = room_type_rate_plans.rate_plan_id")
      .where(room_type_id: room_type_id, rate_plans: { kind: kind })
      .maximum(:rate_plan_id)
  end
end
