# frozen_string_literal: true

module ChannelManagers
  # Mirrors per-OTA room overrides (close-outs and allotments) into Channex
  # availability rules titled "PMS Override", with our ChannelRoomRate rows as
  # the source of truth.
  #
  # A push only covers the dates that changed, but a rule can span far more:
  # a 1-30 Nov Agoda close-out overlaps a push for 10 Nov. Every rule the push
  # touches is replaced, so the rebuild widens to cover those rules in full
  # rather than shrinking the close-out to the pushed dates.
  #
  # Rules a hotel makes by hand on the inventory dashboard are also titled
  # "PMS Override" by default, but they belong to ChannelAvailabilityRule
  # records and sync on their own. Their Channex ids come in as
  # owned_rule_ids and are never touched here.
  class ChannexAvailabilityRules
    TITLE = "PMS Override"
    PAGE_LIMIT = 100
    ALL_DAYS = %w[mo tu we th fr sa su].freeze

    Rule = Struct.new(:id, :channel_ids, :room_type_ids, :dates, keyword_init: true)

    # external_room_type_ids maps our room type ids to their Channex ids, for
    # the room types this push covers.
    def initialize(client:, property_id:, external_room_type_ids:, owned_rule_ids: [], today: Date.current)
      @client = client
      @property_id = property_id
      @external_room_type_ids = external_room_type_ids
      @owned_rule_ids = owned_rule_ids.to_set
      @today = today
    end

    def call(date_range)
      return if @external_room_type_ids.empty?
      # Hotels that never set a per-OTA override have no rules to keep in step,
      # so they skip the extra call on every push.
      return unless ChannelRoomRate.exists?(room_type_id: @external_room_type_ids.keys, rate_plan_id: nil)

      rules = fetch_rules
      return if rules.nil?

      pairs_to_rebuild(date_range, rules).each do |room_type_id, channel_id|
        rebuild(room_type_id, channel_id, date_range, rules)
      end
    end

    private

    # Pairs with an override in the window, plus pairs whose rule in the window
    # no longer has any override behind it, so it gets cleared.
    def pairs_to_rebuild(date_range, rules)
      from_overrides = ChannelRoomRate
        .where(room_type_id: @external_room_type_ids.keys, rate_plan_id: nil, date: date_range)
        .distinct
        .pluck(:room_type_id, :channel_id)

      room_type_ids_by_external = @external_room_type_ids.invert
      from_rules = rules.select { |rule| rule.dates.overlaps?(date_range) }.flat_map do |rule|
        rule.room_type_ids.filter_map { |external_id| room_type_ids_by_external[external_id] }
          .product(rule.channel_ids)
      end

      (from_overrides + from_rules).uniq
    end

    def rebuild(room_type_id, channel_id, date_range, rules)
      external_id = @external_room_type_ids.fetch(room_type_id)
      own_rules = rules.select { |rule| rule.channel_ids.include?(channel_id) && rule.room_type_ids.include?(external_id) }
      span = span_covering(date_range, own_rules)
      replaced = own_rules.select { |rule| rule.dates.overlaps?(span) }

      # Past nights are no use to an OTA, and a rule starting in the past
      # risks being refused, so the rebuild starts no earlier than today.
      overrides = ChannelRoomRate.where(
        room_type_id: room_type_id, channel_id: channel_id, rate_plan_id: nil, date: [ span.begin, @today ].max..span.end
      )

      # New rules go up before the old ones come down: if Channex refuses one,
      # the old rule stays and keeps its dates closed rather than leaving a gap.
      created = rule_specs(overrides).map do |spec|
        create_rule(channel_id: channel_id, external_id: external_id, **spec)
      end
      if created.any?(&:nil?)
        Rails.logger.warn("Channex availability rules kept #{replaced.size} old rule(s) after a refused create property_id=#{@property_id}")
        return
      end

      replaced.each do |rule|
        request(:delete, "/channel_availability_rules/#{rule.id}", context: "delete rule #{rule.id}")
      end
    end

    def rule_specs(overrides)
      close_outs = date_ranges(overrides.select(&:stop_sell).map(&:date)).map { |dates| { type: "close_out", dates: dates } }
      allotments = overrides.select { |o| o.availability.present? && !o.stop_sell }.group_by(&:availability).flat_map do |value, rows|
        date_ranges(rows.map(&:date)).map { |dates| { type: "max_availability", value: value.to_i, dates: dates } }
      end
      close_outs + allotments
    end

    # Grows the window until no rule it overlaps reaches past it, since each of
    # those rules is about to be deleted and must be rebuilt in full.
    def span_covering(date_range, own_rules)
      span = date_range
      loop do
        touching = own_rules.select { |rule| rule.dates.overlaps?(span) }
        wider = [ span.begin, *touching.map { _1.dates.begin } ].min..[ span.end, *touching.map { _1.dates.end } ].max
        return span if wider == span

        span = wider
      end
    end

    def create_rule(type:, channel_id:, external_id:, dates:, value: nil)
      body = {
        title: TITLE,
        type: type,
        value: value,
        affected_channels: [ channel_id ],
        affected_room_types: [ external_id ],
        days: ALL_DAYS,
        start_date: dates.first.to_s,
        end_date: dates.last.to_s,
        property_id: @property_id
      }.compact

      request(:post, "/channel_availability_rules", { channel_availability_rule: body }, context: "create #{type} rule")
    end

    # Every PMS Override rule on the property. Channex pages this list (10 by
    # default, newest first), so reading only the first page would miss older
    # rules and leave them in place forever. Nil when the list can't be read,
    # because rebuilding without it would duplicate rules.
    def fetch_rules
      rules = []
      page = 1

      loop do
        response = request(
          :get,
          "/channel_availability_rules",
          { "filter" => { "property_id" => @property_id }, "pagination" => { "page" => page, "limit" => PAGE_LIMIT } },
          context: "list rules"
        )
        return nil if response.nil?

        data = Array(response["data"])
        rules.concat(data.filter_map { |rule| parse_rule(rule) })

        total = response.dig("meta", "total").to_i
        break if data.empty? || page * PAGE_LIMIT >= total

        page += 1
      end

      rules
    end

    def parse_rule(rule)
      attributes = rule["attributes"] || {}
      return unless attributes["title"] == TITLE
      return if @owned_rule_ids.include?(rule["id"])

      start_date = Date.parse(attributes["start_date"].to_s)
      end_date = Date.parse(attributes["end_date"].to_s)
      Rule.new(
        id: rule["id"],
        channel_ids: Array(attributes["affected_channels"]),
        room_type_ids: Array(attributes["affected_room_types"]),
        dates: start_date..end_date
      )
    rescue Date::Error
      nil
    end

    # Retryable failures raise so the whole push retries; rebuilding from our
    # rows is safe to repeat. Anything else is logged and skipped.
    def request(verb, path, payload = nil, context:)
      response = payload.nil? ? @client.public_send(verb, path) : @client.public_send(verb, path, payload)
      return response unless response[:error] || response["error"]

      details = response[:details] || response["details"] || response
      if response[:retryable] || response["retryable"]
        raise Channex::Client::RetryableRequestError, "Availability rules #{context} failed: #{details}"
      end

      Rails.logger.warn("Channex availability rules #{context} failed property_id=#{@property_id}: #{details.inspect}")
      nil
    end

    def date_ranges(dates)
      dates.uniq.sort.slice_when { |a, b| b != a + 1 }.map { |run| run.first..run.last }
    end
  end
end
