# frozen_string_literal: true

module GuestUI
  # One amenity a guest can use: where it is, when it opens, what it costs,
  # and whether to book.
  #
  # The facts show at once, not behind a tap. A guest opens the Amenities page
  # to compare them ("is the pool still open, is the gym free"), and a closed
  # list makes them open every one.
  #
  # Each fact is a term with an icon. The icon is decorative; the term is read
  # out, so a screen reader hears "Hours: Open 24 hours", not a bare time.
  class AmenityCard < GuestUI::BaseComponent
    # The icon for an amenity: its own where a word of its slug fits, else its
    # category's. Whole words, so "bar" does not match "barbecue".
    ICONS = {
      %w[pool swimming] => "waves-ladder",
      %w[fitness gym] => "dumbbell",
      %w[spa massage sauna wellness] => "flower-2",
      %w[archery] => "target",
      %w[laundry ironing] => "shirt",
      %w[wifi internet] => "wifi",
      %w[parking valet] => "car",
      %w[bicycle bike bikes] => "bike",
      %w[bar wine] => "wine",
      %w[coffee cafe] => "coffee",
      %w[restaurant breakfast dining] => "utensils",
      %w[kids child children baby] => "baby"
    }.freeze
    CATEGORY_ICONS = {
      "Parking" => "car",
      "Food And Drink" => "utensils",
      "Pets" => "paw-print",
      "Services" => "concierge-bell",
      "Outdoors" => "trees",
      "Safety And Security" => "shield-check",
      "Activities" => "ticket"
    }.freeze

    def self.icon_for(slug:, category: nil)
      words = slug.to_s.split("_")
      ICONS.find { |keywords, _icon| keywords.intersect?(words) }&.last ||
        CATEGORY_ICONS.fetch(category.to_s, "sparkles")
    end

    def initialize(name:, icon: "sparkles", category: nil, location: nil, hours: nil, price: nil,
                   book_ahead: false, booking: nil, notes: nil, class: nil, **attributes)
      @name = name
      @icon = icon
      @category = category
      @location = location
      @hours = hours
      @price = price
      @book_ahead = book_ahead
      @booking = booking
      @notes = notes
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    private

    attr_reader :name, :icon, :category, :notes

    def book_ahead? = @book_ahead

    # The booking line says how to book. Without one, the badge is enough.
    def booking = (@booking.presence if book_ahead?)

    def facts
      [
        [ "Location", "map-pin", @location ],
        [ "Hours", "clock", @hours ],
        [ "Price", "tag", @price ]
      ].select { |_label, _icon, value| value.present? }
    end

    def empty? = facts.empty? && booking.blank? && notes.blank?

    def card_attributes
      @attributes.merge(class: tw_merge("guest-amenity", @class))
    end
  end
end
