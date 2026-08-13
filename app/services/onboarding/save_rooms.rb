# frozen_string_literal: true

module Onboarding
  # Persists the Rooms onboarding spreadsheet as one atomic unit. RoomType stays
  # the domain source of truth; onboarding supplies only the collection
  # orchestration, completion contract, and downstream progress invalidation.
  class SaveRooms
    Result = ApplicationResult.define(:section, :entries)

    SCALAR_FIELDS = %w[
      id client_key _destroy name max_adults max_children quantity
      no_smoking no_pets room_number_mode
    ].freeze
    STRUCTURAL_FIELDS = %i[quantity max_adults max_children room_number_mode room_numbers].freeze

    def initialize(hotel:, actor:, entries:, complete:)
      @hotel = hotel
      @actor = actor
      @raw_entries = entries
      @complete = complete
    end

    def call
      return failure("One or more room categories do not belong to this property.") if foreign_ids.any?

      transition_result = nil
      initial_state = section.state
      structural_change = false

      Hotel.transaction do
        retained_entries.each_with_index do |entry, index|
          room_type = entry["id"].present? ? @hotel.room_types.find(entry["id"]) : @hotel.room_types.build
          previous_signature = structural_signature(room_type) if room_type.persisted?
          new_record = room_type.new_record?

          result = HotelPortal::RoomTypes::SaveRoomType.new(
            hotel: @hotel,
            room_type: room_type,
            params: attributes_for(entry, room_type)
          ).call

          unless result.success?
            @error = "Room #{index + 1}: #{result.room_type.errors.full_messages.to_sentence}"
            raise ActiveRecord::Rollback
          end

          structural_change ||= new_record || previous_signature != structural_signature(result.room_type)
        end

        deleted_entries.each do |entry|
          room_type = @hotel.room_types.find(entry["id"])
          result = HotelPortal::RoomTypes::DestroyRoomType.new(room_type: room_type).call
          unless result.success?
            @error = "#{room_type.name}: #{result.errors.full_messages.to_sentence}"
            raise ActiveRecord::Rollback
          end

          structural_change = true
        end

        @hotel.room_types.reset
        if @complete && completion_error.present?
          @error = completion_error
          raise ActiveRecord::Rollback
        end

        if structural_change
          unless invalidate_completed_rooms(initial_state).success?
            @error = "Rooms progress could not be invalidated."
            raise ActiveRecord::Rollback
          end

          invalidation = InvalidateDependentSections.call(
            hotel: @hotel,
            section_keys: [ "rates_availability" ],
            actor: @actor,
            source: "room_structure_change",
            explanation: "Room quantities, occupancy, or numbering changed. Review pricing and availability against the updated rooms.",
            invalidated_by: "rooms"
          )
          unless invalidation.success?
            @error = invalidation.error
            raise ActiveRecord::Rollback
          end
        end

        transition_result = transition_after_save(initial_state:, structural_change:)
        raise ActiveRecord::Rollback unless transition_result.success?
      end

      if @error.present?
        @hotel.room_types.reset
        return failure(@error)
      end
      return failure(transition_result.error, section: transition_result.section) unless transition_result&.success?

      Result.success(section: transition_result.section, entries: persisted_entries)
    rescue ActiveRecord::RecordNotFound
      failure("One or more room categories do not belong to this property.")
    end

    private

    def entries
      @entries ||= begin
        collection = if @raw_entries.respond_to?(:to_unsafe_h)
                       @raw_entries.to_unsafe_h.values
        elsif @raw_entries.is_a?(Hash)
                       @raw_entries.values
        else
                       Array(@raw_entries)
        end

        collection.map do |entry|
          values = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry.to_h
          normalized = values.stringify_keys.slice(*SCALAR_FIELDS)
          normalized.transform_values! { |value| value.is_a?(String) ? value.strip : value }
          normalized["amenities"] = Array(values["amenities"] || values[:amenities]).map(&:to_s).reject(&:blank?).uniq
          normalized["room_numbers"] = Array(values["room_numbers"] || values[:room_numbers]).map(&:to_s).map(&:strip).reject(&:blank?)
          normalized
        end
      end
    end

    def retained_entries
      @retained_entries ||= entries.reject { |entry| destroy?(entry) || blank_new_entry?(entry) }
    end

    def deleted_entries
      @deleted_entries ||= entries.select { |entry| entry["id"].present? && destroy?(entry) }
    end

    def foreign_ids
      @foreign_ids ||= begin
        submitted = entries.filter_map { |entry| entry["id"].presence }.uniq
        submitted - @hotel.room_types.where(id: submitted).pluck(:id).map(&:to_s)
      end
    end

    def destroy?(entry)
      ActiveModel::Type::Boolean.new.cast(entry["_destroy"])
    end

    def blank_new_entry?(entry)
      entry["id"].blank? && %w[name max_adults max_children quantity].all? { |field| entry[field].blank? }
    end

    def attributes_for(entry, room_type)
      {
        name: entry["name"],
        max_adults: entry["max_adults"],
        max_children: entry["max_children"],
        quantity: entry["quantity"],
        smoking_allowed: !boolean(entry["no_smoking"]),
        pets_allowed: !boolean(entry["no_pets"]),
        amenities: entry["amenities"],
        room_number_mode: normalized_number_mode(entry),
        room_numbers: entry["room_numbers"]
      }.tap { |attributes| attributes[:base_price] = 0 if room_type.new_record? }
    end

    def normalized_number_mode(entry)
      return "custom" if entry["room_number_mode"] == "custom"

      "range"
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def structural_signature(room_type)
      STRUCTURAL_FIELDS.map do |field|
        value = room_type.public_send(field)
        field == :room_numbers ? Array(value).map(&:to_s) : value
      end
    end

    def completion_error
      rooms = @hotel.room_types.to_a
      return "Add at least one room category before continuing." if rooms.empty?

      rooms.each_with_index do |room_type, index|
        missing = []
        missing << "room category" if room_type.name.blank?
        missing << "total rooms of at least 1" unless room_type.quantity.to_i >= 1
        missing << "maximum adults of at least 1" unless room_type.max_adults.to_i >= 1
        missing << "maximum children" if room_type.max_children.nil? || room_type.max_children.to_i.negative?
        next if missing.empty? && room_type.valid?

        details = (missing + room_type.errors.full_messages).uniq.to_sentence
        return "Room #{index + 1}: complete #{details}."
      end

      nil
    end

    def invalidate_completed_rooms(initial_state)
      return Result.success(section: section, entries: entries) unless initial_state == "complete"

      UpdateSection.new(
        hotel: @hotel,
        section_key: "rooms",
        state: "needs_attention",
        actor: @actor,
        metadata: {
          source: "room_structure_change",
          explanation: "Room quantities, occupancy, or numbering changed. Review and confirm the Rooms step again."
        }
      ).call
    end

    def transition_after_save(initial_state:, structural_change:)
      if @complete
        update_section("complete")
      elsif structural_change && initial_state == "complete"
        Result.success(section: section, entries: entries)
      elsif initial_state.in?(%w[complete needs_attention])
        Result.success(section: section, entries: entries)
      else
        update_section("in_progress")
      end
    end

    def update_section(state)
      UpdateSection.new(
        hotel: @hotel,
        section_key: "rooms",
        state: state,
        actor: @actor,
        metadata: {
          source: "room_setup",
          room_count: @hotel.room_types.size,
          pricing_deferred: true
        }
      ).call
    end

    def section
      @section ||= begin
        InitializeProgress.new(hotel: @hotel, actor: @actor).call
        @hotel.onboarding_sections.find_by!(section_key: "rooms")
      end
    end

    def persisted_entries
      @hotel.room_types.reload.order(:created_at, :id).map do |room_type|
        {
          "id" => room_type.id.to_s,
          "client_key" => "room-#{room_type.id}",
          "name" => room_type.name,
          "max_adults" => room_type.max_adults.to_s,
          "max_children" => room_type.max_children.to_s,
          "quantity" => room_type.quantity.to_s,
          "no_smoking" => (!room_type.smoking_allowed?).to_s,
          "no_pets" => (!room_type.pets_allowed?).to_s,
          "amenities" => room_type.amenities,
          "room_number_mode" => room_type.room_number_mode,
          "room_numbers" => room_type.room_numbers
        }
      end
    end

    def failure(message, section: nil)
      Result.failure(
        message.presence || "Rooms could not be saved.",
        section: section || @hotel.onboarding_sections.find_by(section_key: "rooms"),
        entries: entries
      )
    end
  end
end
