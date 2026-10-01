# frozen_string_literal: true

namespace :sandbay do
  desc "Seed Sand Bay Resort (per-person hotel) so the eZee reservation CSV can be imported into it"
  task seed_hotel: :environment do
    # Rooms and capacity are the property's own room list. Prices are per
    # person by number of adults, as entered in Room Inventory.
    categories = {
      "Standard Twin" => { rooms: %w[B1 B2 B3 B4 B5 B6 B7 B8 B9 B10], adults: 3, children: 1, grid: :standard },
      "Standard Triple" => { rooms: %w[E1 E2 E3 E4], adults: 3, children: 1, grid: :standard },
      "Standard Family" => { rooms: %w[D1 D2 D3 D4 D5 D6], adults: 5, children: 2, grid: :standard },
      "Deluxe Twin" => { rooms: %w[C2 C4 C6 F1 F2 F3 F4], adults: 2, children: 1, grid: :deluxe },
      "Deluxe King" => { rooms: %w[A2 A4 A6 A8 A10 C1 C3 C5 C7], adults: 2, children: 1, grid: :deluxe },
      "Deluxe Super King" => { rooms: %w[A1 A3 A5 A7 A9], adults: 3, children: 1, grid: :deluxe }
    }.freeze

    # Price for ONE adult; the rate plan charges it per head, so n adults cost
    # n times as much. Children pay half of one adult, as a fixed amount per category
    # (a child age band); child_price_multiplier is only the fallback when a
    # booking has no child ages.
    # "Standard Rate" is the base plan everywhere except Standard Family, which
    # has no Standard Rate at all: its base rate is International Publish Rate.
    # Its Standard Rate plan is archived and carries no prices.
    plans = {
      "Standard Rate" => { standard: 550, deluxe: 600 },
      "International Agent Rate" => { standard: 600, deluxe: 650 },
      "International Publish Rate" => { standard: 850, deluxe: 900 },
      "Malaysian Agent Rate" => { standard: 475, deluxe: 525 },
      "Malaysian Publish Rate" => { standard: 575, deluxe: 625 },
      "Perfect Holiday" => { standard: 420, deluxe: 420 },
      "Super Sightseeing" => { standard: 540, deluxe: 540 }
    }.freeze

    # What a child pays, as a share of one adult's price (the property: "50% off").
    child_share = 0.5.to_d

    # Boat timetable: slot time, and the meals served on that boat.
    boat_in = { "10:30" => %i[lunch hi_tea dinner], "12:30" => %i[lunch hi_tea dinner], "15:30" => %i[hi_tea dinner] }
    boat_out = { "09:30" => %i[breakfast], "11:30" => %i[breakfast], "14:30" => %i[breakfast lunch] }

    account = Account.find_by!(slug: ENV.fetch("ACCOUNT", "sample-account"))

    hotel = Hotel.find_or_initialize_by(account: account, name: "Sand Bay Resort")
    # Sell mode cannot be changed once a hotel exists, so it is only set here.
    hotel.sell_mode = "per_person" if hotel.new_record?
    hotel.city = "Semporna"
    hotel.country = "Malaysia"
    hotel.status = "live"
    hotel.address = "Pulau Mabul, 91300 Semporna, Sabah"
    hotel.star_rating = 3
    hotel.default_currency = "MYR"
    hotel.tourism_tax_enabled = true
    hotel.tourism_tax_amount = 10.0
    hotel.allow_boat_information = true
    hotel.guest_registration_card_terms ||= "Standard registration card terms."
    hotel.save!
    puts "Hotel ##{hotel.id} '#{hotel.name}' (#{hotel.sell_mode}) ready."

    PropertyPolicy.find_or_initialize_by(hotel: hotel).tap do |policy|
      policy.check_in_time = "15:00"
      policy.check_out_time = "12:00"
      policy.currency = "MYR"
      policy.save!
    end

    Financials::EnsureDefaultGlMaps.call(hotel)

    hotel.hotel_boat_setting || hotel.create_hotel_boat_setting!(
      breakfast_time: "07:00", lunch_time: "12:00", hi_tea_time: "16:00", dinner_time: "19:00"
    )
    { "boat_in" => boat_in, "boat_out" => boat_out }.each do |kind, slots|
      slots.each do |time, meals|
        slot = hotel.hotel_boat_schedules.find_or_initialize_by(kind: kind, time: time)
        slot.assign_attributes(%i[breakfast lunch hi_tea dinner].index_with { |meal| meals.include?(meal) }
                                                               .transform_keys { |meal| "has_#{meal}" })
        slot.save!
      end
    end
    puts "  boat timetable: in #{boat_in.keys.join(', ')} / out #{boat_out.keys.join(', ')}"

    room_types = categories.map do |name, spec|
      room_type = Rooms::SaveSeedRoomType.call!(
        hotel: hotel,
        attributes: { name: name, room_number_mode: "custom", quantity: spec[:rooms].size,
                      base_price: plans.fetch("Standard Rate")[spec[:grid]], max_adults: spec[:adults],
                      max_children: spec[:children], room_numbers: spec[:rooms] }
      )
      [ room_type, spec ]
    end

    room_types.each do |room_type, spec|
      family = room_type.name == "Standard Family"
      base_plan_name = family ? "International Publish Rate" : "Standard Rate"

      plans.each do |plan_name, per_head|
        next if family && plan_name == "Standard Rate"

        plan = if plan_name == "Standard Rate"
          room_type.standard_rate_plan
        else
          RatePlan.find_or_create_by!(hotel: hotel, name: plan_name) { |new_plan| new_plan.kind = "custom" }
        end
        plan.update!(child_price_multiplier: 0.5)

        assignment = RoomTypeRatePlan.find_or_create_by!(room_type: room_type, rate_plan: plan)
        assignment.update!(pricing_mode: "fixed")
        (1..spec[:adults]).each do |adults|
          price = assignment.occupancy_prices.find_or_initialize_by(adults: adults)
          price.update!(price: per_head.fetch(spec[:grid]) * adults)
        end

        # A child pays a fixed amount: half of one adult's price on this plan
        # and category. An amount, not the plan's percentage, so a single-
        # occupancy surcharge never changes what a child costs.
        band = plan.rate_plan_age_bands.find_or_initialize_by(min_age: 0, max_age: 17)
        band.update!(label: "Child", pricing_mode: "amount", price_value: 0)
        child_price = assignment.age_band_prices.find_or_initialize_by(rate_plan_age_band: band)
        child_price.update!(price: (per_head.fetch(spec[:grid]) * child_share).round(2))
      end

      # The plan the property leads with (the "Base rate" badge). A display
      # choice, so it is set after every assignment exists.
      room_type.room_type_rate_plans.where(primary_plan: true).update_all(primary_plan: false)
      room_type.room_type_rate_plans.joins(:rate_plan).find_by!(rate_plans: { name: base_plan_name })
               .update!(primary_plan: true)
      # Standard Family has no Standard Rate: archive that category's own plan.
      room_type.system_rate_plan("standard")&.update!(archived_at: Time.current) if family
      puts "  #{room_type.name.ljust(18)} #{spec[:rooms].size} rooms, up to #{spec[:adults]} adults"
    end

    owner_role = Role.find_by(account: account, slug: "hotel_owner")
    if owner_role
      User.where(email: [ "owner@sample.com", "owner@example.com" ]).find_each do |user|
        UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: owner_role)
      end
    end

    puts "\nSeeded. Import at:"
    puts "  /admin/hotels/#{hotel.id}/reservation_import/new"
    puts "  file: spec/fixtures/files/ezee_reservation_csv_sample.csv (or the real export)"
  end
end
