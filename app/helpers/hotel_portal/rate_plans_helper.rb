# frozen_string_literal: true

module HotelPortal
  module RatePlansHelper
    # Per-room-type pricing submits as a plain hash under
    # rate_plan[room_type_pricing][<room_type_id>] rather than a nested
    # association, so there is no builder to hand PanelsUI. fields_for with a
    # string scope over this stand-in produces exactly those names.
    RoomTypePricingScope = Struct.new(:pricing_mode, :pricing_value)

    def room_type_pricing_choices
      [
        { label: "I'll set prices by date", value: "fixed" },
        { label: "Adjust Standard Rate by %", value: "multiplier" },
        { label: "Adjust Standard Rate by amount", value: "offset" }
      ]
    end

    # Backs the age-band "preview using" selector. It exists only to pick which
    # room type the example prices are calculated against, so it is scoped
    # outside :rate_plan and never reaches strong params — but PanelsUI selects
    # all require a real form builder, hence the stand-in object.
    PreviewScope = Struct.new(:room_type_id)

    # "Walk-in"/"Corporate"/"OTA" say what the row is; "virtual tier" is an
    # internal notion staff have no reason to learn.
    TIER_LABELS = { "walk_in" => "Walk-in", "corporate" => "Corporate", "ota" => "OTA" }.freeze

    def rate_tier_label(rate_plan)
      TIER_LABELS[rate_plan.kind]
    end

    def age_band_pricing_choices
      [
        { label: "% of the adult rate", value: "multiplier" },
        { label: "Fixed price per child", value: "amount" }
      ]
    end
  end
end
