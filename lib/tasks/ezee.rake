# frozen_string_literal: true

namespace :ezee do
  desc "Seed the dev hotel the eZee reservation-list fixture imports into"
  task seed_hotel: :environment do
    # The fixture carries this property's real inventory: 64 rooms across six
    # categories, and room number implies room type with no exceptions. Anything
    # that does not match makes the import fail on availability rather than on
    # anything interesting, so the seed mirrors the file exactly.
    ROOMS_BY_TYPE = {
      "DLX" => { rooms: %w[A1 A2 A3 A4 B1 B2 B3 B4 C1 C2 C3 C4 H1 H2 H3 H4
                           K1 K2 K3 K4 M1 M2 M3 M4 N1 N2],
                 base_price: 305.0, max_adults: 3 },
      "STD" => { rooms: %w[D1 D2 D3 D4 E1 E2 E3 E4 G1 G2 G3 G4
                           J1 J2 J3 J4 L1 L2 L3 L4 R3 R4],
                 base_price: 225.0, max_adults: 3 },
      "SP STD" => { rooms: %w[P1 P2 P3 P4 R1 R2], base_price: 250.0, max_adults: 3 },
      "SDLX S" => { rooms: %w[S1 S2 S3 S4], base_price: 330.0, max_adults: 3 },
      "SDLX N" => { rooms: %w[N3 N4], base_price: 330.0, max_adults: 3 },
      "STD VALLEY" => { rooms: %w[F1 F2 F3 F4], base_price: 259.0, max_adults: 3 }
    }.freeze

    account = Account.find_by!(slug: "sample-account")

    hotel = Hotel.find_or_initialize_by(account: account, name: "Kinabalu Pine Resorts")
    hotel.city = "Kundasang"
    hotel.country = "Malaysia"
    hotel.status = "live"
    hotel.address = "Jalan Kundasang, 89308 Ranau, Sabah"
    hotel.star_rating = 3
    hotel.default_currency = "MYR"
    hotel.sell_mode = "per_room"
    # Tourism tax stays enabled because the property really does charge it. The
    # importer leaves guest_country blank, which is what keeps it off imported
    # bookings -- see docs/ezee-reservation-import.md section 2.2. Disabling it
    # here would hide a regression in that behaviour.
    hotel.tourism_tax_enabled = true
    hotel.tourism_tax_amount = 10.0
    hotel.guest_registration_card_terms ||= "Standard registration card terms."
    hotel.save!
    puts "Hotel ##{hotel.id} '#{hotel.name}' ready."

    PropertyPolicy.find_or_initialize_by(hotel: hotel).tap do |policy|
      policy.check_in_time = "14:00"
      policy.check_out_time = "12:00"
      policy.currency = "MYR"
      policy.save!
    end

    Financials::EnsureDefaultGlMaps.call(hotel)

    room_types = ROOMS_BY_TYPE.map do |name, spec|
      room_type = Rooms::SaveSeedRoomType.call!(
        hotel: hotel,
        attributes: {
          name: name, room_number_mode: "custom", quantity: spec[:rooms].size,
          base_price: spec[:base_price], max_adults: spec[:max_adults],
          max_children: 2, room_numbers: spec[:rooms]
        }
      )
      puts "  #{name.ljust(11)} #{spec[:rooms].size} rooms @ #{spec[:base_price]}"
      room_type
    end

    # One plan per eZee rate type, so the file's Rate Type column has somewhere
    # to land once the importer maps it. Creating the category already creates
    # its system plans, and standard_rate_plan is what the minimal importer
    # actually uses -- these are here for the mapping step that follows.
    %w[Agent Promo Agoda Corp TIKET Pub Comp Room].each do |name|
      plan = RatePlan.find_or_initialize_by(hotel: hotel, name: name)
      plan.kind = "custom"
      plan.sell_mode = "per_room"
      plan.currency = "MYR"
      plan.save!
      room_types.each { |rt| RoomTypeRatePlan.find_or_create_by!(room_type: rt, rate_plan: plan) }
    end
    puts "  8 rate plans linked to every category."

    owner_role = Role.find_by!(account: account, slug: "hotel_owner")
    User.where(email: [ "owner@sample.com", "owner@example.com" ]).find_each do |user|
      UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: owner_role)
    end

    puts "\nSeeded. Import at:"
    puts "  /admin/hotels/#{hotel.id}/reservation_import/new"
    puts "  file: spec/fixtures/files/ezee_reservation_list_sample.xls"
  end
end

namespace :ezee do
  desc "Delete every imported booking from a hotel so the import can be re-run clean"
  task :reset_import, [ :hotel_id ] => :environment do |_task, args|
    hotel = Hotel.find(args.fetch(:hotel_id))
    ids = hotel.bookings.where.not(external_reference: nil).pluck(:id)
    puts "Removing #{ids.size} imported bookings from #{hotel.name}..."

    # Almost every booking association is dependent: :restrict_with_error, so a
    # plain destroy is refused and hand-listing the tables turns into whack-a-mole.
    # These are freshly imported reservations with nothing behind them, so the
    # dependent rows are found by walking the foreign keys and deleted leaves
    # first. Development only -- it does not check whether a booking has been
    # invoiced.
    connection = ActiveRecord::Base.connection
    referencing = Hash.new { |cache, table| cache[table] = connection.tables.flat_map { |other|
      connection.foreign_keys(other).select { |fk| fk.to_table == table }.map { |fk| [ other, fk.column ] }
    } }

    purge = lambda do |table, keys, depth|
      return if keys.empty? || depth > 6

      referencing[table].each do |child_table, column|
        child_ids = connection.select_values(
          "SELECT id FROM #{connection.quote_table_name(child_table)} " \
          "WHERE #{connection.quote_column_name(column)} IN (#{keys.join(',')})"
        )
        next if child_ids.empty?

        purge.call(child_table, child_ids, depth + 1)
        connection.delete("DELETE FROM #{connection.quote_table_name(child_table)} " \
                          "WHERE #{connection.quote_column_name(column)} IN (#{keys.join(',')})")
      end
    end

    group_ids = Booking.where(id: ids).distinct.pluck(:group_booking_id).compact
    if ids.any?
      purge.call("bookings", ids, 0)
      Booking.where(id: ids).delete_all
    end
    # Groups the deleted bookings belonged to, plus any this hotel is left
    # holding that no longer have a booking in them -- including orphans a
    # half-finished earlier run left behind.
    orphan_ids = hotel.group_bookings.where.missing(:bookings).pluck(:id)
    group_ids = (group_ids + orphan_ids).uniq
    if group_ids.any?
      purge.call("group_bookings", group_ids, 0)
      GroupBooking.where(id: group_ids).delete_all
    end

    # Creating a booking decrements the room-type inventory for each night of
    # the stay. Deleting the booking does not put that back, so without this a
    # second import run starves on inventory the first run consumed and looks
    # like a broken importer. With no row for a date, availability falls back to
    # every configured room, which is the pre-import state.
    inventory = RoomInventory.where(room_type_id: hotel.room_types.select(:id))
    puts "Clearing #{inventory.count} room inventory rows."
    inventory.delete_all

    ReservationImport.where(hotel_id: hotel.id).destroy_all

    puts "Done. #{hotel.bookings.count} bookings remain, #{hotel.group_bookings.count} groups."
  end
end
