# frozen_string_literal: true

module Public::HotelsHelper
  ICON_MAPPING = {
    "General" => [ "general", "cog" ],
    "Services" => [ "services", "concierge-bell" ],
    "Parking" => [ "parking", "square-parking" ],
    "Safety And Security" => [ "safety", "shield-check" ],
    "Security" => [ "security", "shield-check" ],
    "Food And Drink" => [ "dining", "utensils" ],
    "Kitchen" => [ "kitchen", "cooking-pot" ],
    "Activities" => [ "activities", "list-todo" ],
    "Outdoors" => [ "outdoors", "tent-tree" ],
    "Outside" => [ "outside", "trees" ],
    "Pets" => [ "pets", "paw-print" ],
    "In Room" => [ "room", "bed" ],
    "Bathroom" => [ "bathroom", "bath" ],
    "View" => [ "view", "view" ]
  }.freeze

  DEFAULT_ICON = [ "facility", "store" ].freeze

  def category_icon(category)
    icon_id, icon_name = ICON_MAPPING[category] || DEFAULT_ICON

    svg_icon = if Rails.root.join("app/assets/svg/icons", "#{icon_name}.svg").exist?
                 cached_icon(icon_name, library: :"", variant: :".", class: "w-[16px] h-[16px] text-brand-secondary")
    else
                 cached_icon(icon_name, class: "w-[16px] h-[16px] text-brand-secondary")
    end

    "<div id=\"icon-#{icon_id}\">#{svg_icon}</div>".html_safe
  end

  def star_rating_icons(rating)
    content_tag(:div, class: "flex text-amber-400 mt-1") do
      rating.to_i.times do
        concat cached_icon("star", library: "phosphor", variant: "fill", class: "w-3 h-3 fill-current")
      end
    end
  end
end
