# frozen_string_literal: true

module CorporatePortal
  # Prices and checks a whole stay: a list of StayLines on one set of dates.
  #
  # Each line is quoted for its own occupancy by AgentStaySearch, the same
  # search the agent browses, so what they are shown and what is booked cannot
  # drift apart. What a search cannot see is the stay as a whole: two lines in
  # the same category draw on the same free rooms, so availability is checked
  # against the total asked of each category, not line by line.
  #
  # A line's rate must be one the property opens to this agency (market included),
  # for that category. The plan is re-checked here rather than trusted from the
  # form, so a hidden plan's id typed into a request is refused like any other.
  class AgentStayCart
    Quote = Struct.new(:line, :room_type, :rate_plan, :option, :error, keyword_init: true) do
      def ok? = error.blank?
      def rooms = line.quantity
      def per_room_amount = option&.per_room_amount
      def total_amount = option&.total_amount
    end

    Result = Struct.new(:quotes, :errors, :nights, keyword_init: true) do
      def success? = errors.empty?
      def rooms = quotes.sum(&:rooms)
      def total_amount = quotes.sum { |quote| quote.total_amount.to_d }
      def currency = quotes.first&.option&.currency
    end

    def self.call(...) = new(...).call

    def initialize(hotel:, relationship:, check_in:, check_out:, lines:)
      @hotel = hotel
      @relationship = relationship
      @check_in = check_in
      @check_out = check_out
      @lines = lines
      @searches = {}
    end

    def call
      return Result.new(quotes: [], errors: [ "Add at least one room." ], nights: 0) if @lines.empty?

      quotes = @lines.map { |line| quote_for(line) }
      errors = quotes.filter_map(&:error)
      errors.concat(date_errors(quotes)) if errors.empty?
      errors.concat(shared_availability_errors(quotes)) if errors.empty?
      nights = quotes.filter_map { |quote| search_for(quote.line)&.nights }.first.to_i

      Result.new(quotes: quotes, errors: errors.uniq, nights: nights)
    end

    private

    def quote_for(line)
      room_type = @hotel.room_types.find_by(id: line.room_type_id)
      return Quote.new(line: line, error: "Choose a room category.") if room_type.blank?
      return Quote.new(line: line, room_type: room_type, error: room_type.occupancy_limit_message) unless room_type.fits?(adults: line.adults, children: line.children)

      rate_plan = resolve_rate_plan(room_type, line)
      return Quote.new(line: line, room_type: room_type, error: "Choose a rate plan.") if rate_plan.blank?

      result = search_for(line)
      return Quote.new(line: line, room_type: room_type, rate_plan: rate_plan, error: result.error) unless result.success?

      option = result.options.find { |candidate| candidate.room_type.id == room_type.id && candidate.rate_plan.id == rate_plan.id }
      error = if option&.restricted?
        "#{rate_plan.name} can't be booked for these dates: #{option.restriction}."
      elsif !option&.available?
        "#{room_type.name} no longer has #{ActionController::Base.helpers.pluralize(line.quantity, 'room')} free for these dates."
      end

      Quote.new(line: line, room_type: room_type, rate_plan: rate_plan, option: option, error: error)
    end

    # A search per distinct occupancy, not per line: two lines for the same party
    # are quoted together.
    def search_for(line)
      @searches[[ line.adults, line.children, line.child_ages, line.quantity ]] ||= AgentStaySearch.call(
        hotel: @hotel, check_in: @check_in, check_out: @check_out,
        adults: line.adults, children: line.children, child_ages: line.child_ages, rooms: line.quantity,
        relationship: @relationship
      )
    end

    def date_errors(quotes)
      result = search_for(quotes.first.line)
      result.success? ? [] : [ result.error ]
    end

    # Lines in one category share its free rooms.
    def shared_availability_errors(quotes)
      quotes.group_by(&:room_type).filter_map do |room_type, group|
        wanted = group.sum(&:rooms)
        free = group.first.option&.available_count.to_i
        next if wanted <= free

        "#{room_type.name} no longer has #{ActionController::Base.helpers.pluralize(wanted, 'room')} free for these dates."
      end
    end

    # The plan the line names, if this agency may book it for this category; with
    # none named, the category's only plan, so a page rendered before plans were
    # selectable still books.
    def resolve_rate_plan(room_type, line)
      offered = @hotel.rate_plans.offered_to_agency(@relationship)
        .joins(:room_type_rate_plans).where(room_type_rate_plans: { room_type_id: room_type.id })
      return offered.find_by(id: line.rate_plan_id) if line.rate_plan_id.present?

      offered.one? ? offered.first : nil
    end
  end
end
