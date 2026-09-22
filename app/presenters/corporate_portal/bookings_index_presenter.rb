# frozen_string_literal: true

module CorporatePortal
  # The filter and pagination state for an agent's own bookings list --
  # which hotel, which status, how many rows, and the choices the view offers
  # for each. Kept out of the controller so index stays about assembling the
  # query, not about what a page size or a status label reads as.
  #
  # Named flat rather than nested under a `Bookings` module: `CorporatePortal`
  # already has services under top-level `Bookings::` (CreateManualBooking,
  # BuildFinancialSnapshot, ...), and a `CorporatePortal::Bookings` namespace
  # would shadow that constant for every file lexically inside `CorporatePortal`.
  class BookingsIndexPresenter
    PAGE_SIZES = [ 25, 50, 100, 200 ].freeze
    DEFAULT_PAGE_SIZE = 25

    attr_reader :relationships, :page_size

    def self.normalize_page_size(value)
      requested = value.to_i
      PAGE_SIZES.include?(requested) ? requested : DEFAULT_PAGE_SIZE
    end

    def initialize(relationships:, hotel_relationship_id: nil, status: nil, statuses_present: [], page_size: DEFAULT_PAGE_SIZE)
      @relationships = relationships
      @hotel_relationship_id = hotel_relationship_id.presence
      @status = status.presence
      @statuses_present = statuses_present
      @page_size = page_size
    end

    # Only worth asking when there is a choice to make -- an account linked to
    # one hotel never needs "All hotels" as an option, and its own name is
    # redundant on every row once it is the only one that could be there.
    def multiple_hotels? = relationships.size > 1

    def selected_relationship
      return nil if @hotel_relationship_id.blank?

      relationships.find { |relationship| relationship.id.to_s == @hotel_relationship_id.to_s }
    end

    def hotel_choices
      [ { label: "All hotels", value: "" } ] +
        relationships.map { |relationship| { label: relationship.hotel.name, value: relationship.id } }
    end

    # Only the statuses this account's own bookings actually carry -- an
    # agent is never shown a filter that would always come back empty.
    def status_choices
      [ { label: "All statuses", value: "" } ] +
        @statuses_present.map { |status| { label: status.titleize, value: status } }
    end

    def selected_status
      @status if @statuses_present.include?(@status)
    end

    def page_size_choices
      PAGE_SIZES.map { |size| { label: size.to_s, value: size } }
    end

    def default_page_size? = page_size == DEFAULT_PAGE_SIZE
  end
end
